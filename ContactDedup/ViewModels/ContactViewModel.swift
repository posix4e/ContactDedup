import Foundation
import Combine
import SwiftUI

@MainActor
class ContactViewModel: ObservableObject {
    @Published var contacts: [ContactData] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var incompleteContacts: [ContactData] = []

    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var errorMessage: String?
    @Published var successMessage: String?

    @Published var importProgress: Double = 0
    @Published var isImporting = false

    // Track dismissed duplicate pairs (stored as sorted UUID pair strings)
    @AppStorage("dismissedDuplicates") private var dismissedDuplicatesData: String = ""
    private var dismissedDuplicates: Set<String> {
        get { Set(dismissedDuplicatesData.split(separator: ",").map(String.init)) }
        set { dismissedDuplicatesData = newValue.joined(separator: ",") }
    }

    // Track last import times per Google account (stored as JSON)
    @AppStorage("googleImportTimes") private var googleImportTimesData: String = "{}"
    private var googleImportTimes: [String: Date] {
        get {
            guard let data = googleImportTimesData.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: Double].self, from: data) else {
                return [:]
            }
            return dict.mapValues { Date(timeIntervalSince1970: $0) }
        }
        set {
            let dict = newValue.mapValues { $0.timeIntervalSince1970 }
            if let data = try? JSONEncoder().encode(dict),
               let string = String(data: data, encoding: .utf8) {
                googleImportTimesData = string
            }
        }
    }

    // Track last LinkedIn import time
    @AppStorage("linkedInImportTime") private var linkedInImportTimeInterval: Double = 0
    var lastLinkedInImportDate: Date? {
        linkedInImportTimeInterval > 0 ? Date(timeIntervalSince1970: linkedInImportTimeInterval) : nil
    }

    private let appleManager = AppleContactsManager.shared
    private let googleImporter = GoogleContactsImporter()
    private let linkedInImporter = LinkedInImporter()
    private let duplicateDetector = DuplicateDetector()

    var similarityThreshold: Double {
        get { duplicateDetector.similarityThreshold }
        set { duplicateDetector.similarityThreshold = newValue }
    }

    @Published var loadingProgress: Double = 0
    @Published var isFindingDuplicates = false
    @Published var duplicateCheckProgress: String = ""

    // MARK: - Load Contacts from Apple

    func loadContacts() {
        Task {
            isLoading = true
            loadingProgress = 0
            loadingMessage = "Loading contacts from Apple..."
            errorMessage = nil

            do {
                loadingProgress = 0.2
                contacts = try await appleManager.fetchAllContacts()

                loadingProgress = 0.6
                loadingMessage = "Analyzing \(contacts.count) contacts..."
                findIncompleteContacts()

                loadingProgress = 0.8
                isLoading = false
                loadingMessage = ""

                // Run duplicate detection separately with its own indicator
                isFindingDuplicates = true
                await findDuplicatesAsync()
                isFindingDuplicates = false

            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
            loadingProgress = 1.0
            loadingMessage = ""
        }
    }

    // MARK: - Duplicate Detection

    func findDuplicates() {
        Task {
            isFindingDuplicates = true
            await findDuplicatesAsync()
            isFindingDuplicates = false
        }
    }

    private func findDuplicatesAsync() async {
        let contactsCopy = contacts
        let detector = duplicateDetector
        let dismissed = dismissedDuplicates
        let total = contactsCopy.count

        duplicateCheckProgress = "0 / \(total)"

        let groups = await Task.detached {
            detector.findDuplicateGroups(in: contactsCopy) { current, name in
                Task { @MainActor in
                    self.duplicateCheckProgress = "\(current) / \(total): \(name)"
                }
            }
        }.value

        duplicateCheckProgress = ""

        // Filter out dismissed groups
        duplicateGroups = groups.filter { group in
            !isGroupDismissed(group, dismissed: dismissed)
        }
    }

    private func isGroupDismissed(_ group: DuplicateGroup, dismissed: Set<String>) -> Bool {
        // A group is dismissed if any pair of contacts in it was dismissed
        // Use appleIdentifier for persistence across app launches (UUIDs change each load)
        let ids = group.contacts.compactMap { $0.appleIdentifier }.sorted()
        guard ids.count >= 2 else { return false }

        for i in 0..<ids.count {
            for j in (i+1)..<ids.count {
                let pairKey = "\(ids[i])|\(ids[j])"
                if dismissed.contains(pairKey) {
                    return true
                }
            }
        }
        return false
    }

    func dismissDuplicateGroup(_ group: DuplicateGroup) {
        // Store all pairs in this group as dismissed
        // Use appleIdentifier for persistence across app launches
        let ids = group.contacts.compactMap { $0.appleIdentifier }.sorted()
        guard ids.count >= 2 else {
            // If no Apple identifiers, just remove from current list
            duplicateGroups.removeAll { $0.id == group.id }
            return
        }

        var newDismissed = dismissedDuplicates
        for i in 0..<ids.count {
            for j in (i+1)..<ids.count {
                let pairKey = "\(ids[i])|\(ids[j])"
                newDismissed.insert(pairKey)
            }
        }
        dismissedDuplicates = newDismissed

        // Remove from current list
        duplicateGroups.removeAll { $0.id == group.id }
    }

    func clearDismissedDuplicates() {
        dismissedDuplicates = []
        findDuplicates()
    }

    func findDuplicatesWithThreshold(_ threshold: Double) {
        duplicateDetector.similarityThreshold = threshold
        findDuplicates()
    }

    // MARK: - Incomplete Contacts (names with no contact info)

    func findIncompleteContacts() {
        incompleteContacts = contacts.filter { $0.isIncomplete }
    }

    // MARK: - Merge Duplicates (syncs to Apple)

    func mergeContacts(_ group: DuplicateGroup, keepingPrimary primaryId: UUID) async {
        guard let primary = group.contacts.first(where: { $0.id == primaryId }) else { return }

        isLoading = true
        loadingMessage = "Merging contacts..."

        do {
            let merged = try appleManager.mergeContacts(group.contacts, into: primary)

            // Update local state
            contacts.removeAll { contact in
                group.contacts.contains { $0.id == contact.id && $0.id != merged.id }
            }
            if let index = contacts.firstIndex(where: { $0.id == merged.id }) {
                contacts[index] = merged
            }

            // Refresh duplicates
            findDuplicates()
            successMessage = "Successfully merged \(group.contacts.count) contacts"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        loadingMessage = ""
    }

    func mergeAllDuplicates() async {
        await mergeGroups(ofType: nil)
    }

    func mergeGroups(ofType matchType: DuplicateMatchType?) async {
        let groupsToMerge: [DuplicateGroup]
        if let matchType = matchType {
            groupsToMerge = duplicateGroups.filter { $0.matchType == matchType }
        } else {
            groupsToMerge = duplicateGroups
        }

        guard !groupsToMerge.isEmpty else { return }

        isLoading = true
        var mergedCount = 0

        for group in groupsToMerge {
            guard let primary = group.contacts.first else { continue }
            loadingMessage = "Merging group \(mergedCount + 1) of \(groupsToMerge.count)..."

            do {
                let merged = try appleManager.mergeContacts(group.contacts, into: primary)
                contacts.removeAll { contact in
                    group.contacts.contains { $0.id == contact.id && $0.id != merged.id }
                }
                if let index = contacts.firstIndex(where: { $0.id == merged.id }) {
                    contacts[index] = merged
                }
                mergedCount += 1
            } catch {
                // Continue with next group
            }
        }

        findDuplicates()
        successMessage = "Merged \(mergedCount) duplicate groups"
        isLoading = false
        loadingMessage = ""
    }

    // MARK: - Delete Contacts (syncs to Apple)

    func deleteContact(_ contact: ContactData) async {
        isLoading = true
        loadingMessage = "Deleting contact..."

        do {
            if let appleId = contact.appleIdentifier {
                try appleManager.deleteContact(identifier: appleId)
            }
            contacts.removeAll { $0.id == contact.id }
            findIncompleteContacts()
            findDuplicates()
            successMessage = "Contact deleted"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        loadingMessage = ""
    }

    func deleteIncompleteContacts(_ contactsToDelete: [ContactData]) async {
        isLoading = true
        let total = contactsToDelete.count

        let appleIds = contactsToDelete.compactMap { $0.appleIdentifier }
        loadingMessage = "Deleting \(total) incomplete contacts..."

        do {
            try appleManager.deleteContacts(identifiers: appleIds)
            let idsToDelete = Set(contactsToDelete.map { $0.id })
            contacts.removeAll { idsToDelete.contains($0.id) }
            findIncompleteContacts()
            successMessage = "Deleted \(total) incomplete contacts"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        loadingMessage = ""
    }

    func deleteAllIncompleteContacts() async {
        await deleteIncompleteContacts(incompleteContacts)
    }

    // MARK: - Helpers

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}

// MARK: - Google Import
extension ContactViewModel {
    func importFromGoogle() async {
        guard let account = GoogleAuthManager.shared.accounts.first else {
            errorMessage = "Please sign in to Google first"
            return
        }
        await importFromGoogle(account: account)
    }

    func importFromGoogle(account: GoogleAccount) async {
        isImporting = true
        importProgress = 0
        loadingMessage = "Importing from \(account.email)..."

        do {
            let result = try await googleImporter.importWithDeduplication(
                from: account,
                existingContacts: contacts
            ) { current, total in
                Task { @MainActor in
                    self.importProgress = Double(current) / Double(total)
                    self.loadingMessage = "Processing \(current) of \(total)..."
                }
            }

            var times = googleImportTimes
            times[account.email] = Date()
            googleImportTimes = times

            contacts = try await appleManager.fetchAllContacts()
            findDuplicates()
            findIncompleteContacts()

            var message = "Import complete: \(result.imported) new"
            if result.merged > 0 { message += ", \(result.merged) merged" }
            if result.skipped > 0 { message += ", \(result.skipped) skipped" }
            if !duplicateGroups.isEmpty {
                message += ". Found \(duplicateGroups.count) duplicate groups to review."
            }
            successMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
        loadingMessage = ""
    }

    func lastImportDate(for email: String) -> Date? {
        googleImportTimes[email]
    }

    func importFromAllGoogleAccounts() async {
        let accounts = GoogleAuthManager.shared.accounts
        guard !accounts.isEmpty else {
            errorMessage = "Please sign in to Google first"
            return
        }

        isImporting = true
        importProgress = 0
        var totalImported = 0
        var totalMerged = 0
        var totalSkipped = 0

        for (index, account) in accounts.enumerated() {
            loadingMessage = "Importing from \(account.email) (\(index + 1)/\(accounts.count))..."

            do {
                let result = try await googleImporter.importWithDeduplication(
                    from: account,
                    existingContacts: contacts
                ) { current, total in
                    Task { @MainActor in
                        let accountProgress = Double(index) / Double(accounts.count)
                        let withinProgress = Double(current) / Double(max(total, 1))
                        self.importProgress = accountProgress + withinProgress / Double(accounts.count)
                    }
                }

                var times = googleImportTimes
                times[account.email] = Date()
                googleImportTimes = times

                totalImported += result.imported
                totalMerged += result.merged
                totalSkipped += result.skipped

                contacts = try await appleManager.fetchAllContacts()
            } catch {
                // Continue with next account
            }
        }

        findDuplicates()
        findIncompleteContacts()

        var message = "Import complete: \(totalImported) new"
        if totalMerged > 0 { message += ", \(totalMerged) merged" }
        if totalSkipped > 0 { message += ", \(totalSkipped) skipped" }
        successMessage = message

        isImporting = false
        loadingMessage = ""
    }
}

// MARK: - Update & LinkedIn Import
extension ContactViewModel {
    func updateContact(_ contact: ContactData) async {
        isLoading = true
        loadingMessage = "Updating contact..."

        do {
            try appleManager.updateContact(contact)
            if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
                contacts[index] = contact
            }
            findDuplicates()
            findIncompleteContacts()
            successMessage = "Contact updated"
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        loadingMessage = ""
    }

    func importFromLinkedIn(url: URL) async {
        isImporting = true
        importProgress = 0
        loadingMessage = "Importing LinkedIn connections..."

        do {
            let result = try await linkedInImporter.importFromCSV(
                url: url,
                existingContacts: contacts
            ) { current, total in
                Task { @MainActor in
                    self.importProgress = Double(current) / Double(total)
                    self.loadingMessage = "Processing \(current) of \(total)..."
                }
            }

            linkedInImportTimeInterval = Date().timeIntervalSince1970

            contacts = try await appleManager.fetchAllContacts()
            findDuplicates()
            findIncompleteContacts()

            var message = "LinkedIn import: \(result.imported) new"
            if result.merged > 0 { message += ", \(result.merged) merged" }
            if result.skipped > 0 { message += ", \(result.skipped) skipped (no email)" }
            if !duplicateGroups.isEmpty {
                message += ". Found \(duplicateGroups.count) duplicate groups to review."
            }
            successMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
        loadingMessage = ""
    }
}
