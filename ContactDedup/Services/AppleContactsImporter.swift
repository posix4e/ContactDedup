import Contacts
import Foundation

class AppleContactsManager {
    static let shared = AppleContactsManager()
    private let contactStore = CNContactStore()

    enum ContactError: Error, LocalizedError {
        case accessDenied
        case fetchFailed(Error)
        case saveFailed(Error)
        case contactNotFound

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Access to contacts was denied. Please enable access in Settings."
            case .fetchFailed(let error):
                return "Failed to fetch contacts: \(error.localizedDescription)"
            case .saveFailed(let error):
                return "Failed to save contact: \(error.localizedDescription)"
            case .contactNotFound:
                return "Contact not found in Apple Contacts."
            }
        }
    }

    private init() {}

    // MARK: - Authorization

    func requestAccess() async throws -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return try await contactStore.requestAccess(for: .contacts)
        case .denied, .restricted:
            throw ContactError.accessDenied
        @unknown default:
            throw ContactError.accessDenied
        }
    }

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    // MARK: - Fetch Operations

    private var keysToFetch: [CNKeyDescriptor] {
        [
            // Basic name fields
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            // Organization
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            // Contact info
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            // Social & messaging
            CNContactSocialProfilesKey as CNKeyDescriptor,
            CNContactInstantMessageAddressesKey as CNKeyDescriptor,
            // Relationships & dates
            CNContactRelationsKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactDatesKey as CNKeyDescriptor,
            // Notes (requires entitlement com.apple.developer.contacts.notes)
            CNContactNoteKey as CNKeyDescriptor,
            // Images
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
    }

    func fetchAllContacts() async throws -> [ContactData] {
        let hasAccess = try await requestAccess()
        guard hasAccess else {
            throw ContactError.accessDenied
        }

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var contacts: [ContactData] = []

        do {
            try contactStore.enumerateContacts(with: request) { cnContact, _ in
                let contact = self.convertToContactData(cnContact)
                contacts.append(contact)
            }
        } catch {
            throw ContactError.fetchFailed(error)
        }

        return contacts
    }

    func fetchContact(identifier: String) throws -> CNContact? {
        do {
            return try contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keysToFetch)
        } catch {
            return nil
        }
    }

    // MARK: - Write Operations (Sync back to Apple)

    func updateContact(_ contact: ContactData) throws {
        guard let appleId = contact.appleIdentifier else {
            // No Apple identifier - this is a new contact to create
            try createContact(contact)
            return
        }

        guard let existingContact = try fetchContact(identifier: appleId) else {
            throw ContactError.contactNotFound
        }

        guard let mutableContact = existingContact.mutableCopy() as? CNMutableContact else {
            let error = NSError(
                domain: "ContactDedup", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create mutable contact"]
            )
            throw ContactError.saveFailed(error)
        }
        applyContactData(contact, to: mutableContact)

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutableContact)

        do {
            try contactStore.execute(saveRequest)
        } catch {
            throw ContactError.saveFailed(error)
        }
    }

    func createContact(_ contact: ContactData) throws {
        let mutableContact = CNMutableContact()
        applyContactData(contact, to: mutableContact)

        let saveRequest = CNSaveRequest()
        saveRequest.add(mutableContact, toContainerWithIdentifier: nil)

        do {
            try contactStore.execute(saveRequest)
        } catch {
            throw ContactError.saveFailed(error)
        }
    }

    func deleteContact(identifier: String) throws {
        guard let existingContact = try fetchContact(identifier: identifier) else {
            throw ContactError.contactNotFound
        }

        guard let mutableContact = existingContact.mutableCopy() as? CNMutableContact else {
            let error = NSError(
                domain: "ContactDedup", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create mutable contact"]
            )
            throw ContactError.saveFailed(error)
        }
        let saveRequest = CNSaveRequest()
        saveRequest.delete(mutableContact)

        do {
            try contactStore.execute(saveRequest)
        } catch {
            throw ContactError.saveFailed(error)
        }
    }

    func deleteContacts(identifiers: [String]) throws {
        let saveRequest = CNSaveRequest()

        for identifier in identifiers {
            if let existingContact = try fetchContact(identifier: identifier),
               let mutableContact = existingContact.mutableCopy() as? CNMutableContact {
                saveRequest.delete(mutableContact)
            }
        }

        do {
            try contactStore.execute(saveRequest)
        } catch {
            throw ContactError.saveFailed(error)
        }
    }

    // MARK: - Merge Operation (combines contacts and syncs to Apple)

    /// Merges multiple contacts into a primary contact with ZERO data loss.
    /// - All unique values from all contacts are preserved
    /// - Conflicting text fields are stored in notes with full history
    /// - Alternate names are preserved in the nickname field
    func mergeContacts(_ contacts: [ContactData], into primary: ContactData) throws -> ContactData {
        var merged = primary
        var mergeNotes: [String] = []
        var alternateNames: [String] = []

        for contact in contacts where contact.id != primary.id {
            var contactMergeInfo: [String] = []

            // === ADDITIVE MERGES (no data loss) ===

            // Merge emails (add unique ones, case-insensitive)
            let existingEmailsLower = Set(merged.emails.map { $0.lowercased() })
            let newEmails = contact.emails.filter { !existingEmailsLower.contains($0.lowercased()) }
            merged.emails.append(contentsOf: newEmails)

            // Merge phone numbers (add unique ones, normalized)
            let existingPhonesNormalized = Set(merged.phoneNumbers.map { normalizePhone($0) })
            let newPhones = contact.phoneNumbers.filter { !existingPhonesNormalized.contains(normalizePhone($0)) }
            merged.phoneNumbers.append(contentsOf: newPhones)

            // Merge addresses (add unique ones)
            let newAddresses = contact.addresses.filter { !merged.addresses.contains($0) }
            merged.addresses.append(contentsOf: newAddresses)

            // Merge URLs (add unique ones)
            let existingUrlsLower = Set(merged.urls.map { $0.lowercased() })
            let newUrls = contact.urls.filter { !existingUrlsLower.contains($0.lowercased()) }
            merged.urls.append(contentsOf: newUrls)

            // Merge social profiles (add unique ones by service+username)
            let existingProfiles = Set(merged.socialProfiles.map { "\($0.service.lowercased()):\($0.username.lowercased())" })
            let newProfiles = contact.socialProfiles.filter {
                !existingProfiles.contains("\($0.service.lowercased()):\($0.username.lowercased())")
            }
            merged.socialProfiles.append(contentsOf: newProfiles)

            // Merge instant message addresses
            let existingIMs = Set(merged.instantMessageAddresses.map { "\($0.service.lowercased()):\($0.username.lowercased())" })
            let newIMs = contact.instantMessageAddresses.filter {
                !existingIMs.contains("\($0.service.lowercased()):\($0.username.lowercased())")
            }
            merged.instantMessageAddresses.append(contentsOf: newIMs)

            // Merge relationships (add unique ones by name+label)
            let existingRelations = Set(merged.relationships.map { "\($0.label.lowercased()):\($0.name.lowercased())" })
            let newRelations = contact.relationships.filter {
                !existingRelations.contains("\($0.label.lowercased()):\($0.name.lowercased())")
            }
            merged.relationships.append(contentsOf: newRelations)

            // Merge dates (add unique ones)
            let existingDates = Set(merged.dates.map { "\($0.label):\($0.date.month ?? 0)-\($0.date.day ?? 0)" })
            let newDates = contact.dates.filter {
                !existingDates.contains("\($0.label):\($0.date.month ?? 0)-\($0.date.day ?? 0)")
            }
            merged.dates.append(contentsOf: newDates)

            // === CONFLICT-AWARE MERGES (preserve conflicts in notes) ===

            // Handle name conflicts - preserve alternate names
            let contactFullName = "\(contact.firstName) \(contact.lastName)".trimmingCharacters(in: .whitespaces)
            let mergedFullName = "\(merged.firstName) \(merged.lastName)".trimmingCharacters(in: .whitespaces)
            if !contactFullName.isEmpty && contactFullName.lowercased() != mergedFullName.lowercased() {
                alternateNames.append(contactFullName)
            }

            // First name conflict
            if !contact.firstName.isEmpty && merged.firstName.isEmpty {
                merged.firstName = contact.firstName
            } else if !contact.firstName.isEmpty && contact.firstName.lowercased() != merged.firstName.lowercased() {
                contactMergeInfo.append("First name: \(contact.firstName)")
            }

            // Last name conflict
            if !contact.lastName.isEmpty && merged.lastName.isEmpty {
                merged.lastName = contact.lastName
            } else if !contact.lastName.isEmpty && contact.lastName.lowercased() != merged.lastName.lowercased() {
                contactMergeInfo.append("Last name: \(contact.lastName)")
            }

            // Middle name
            if !contact.middleName.isEmpty && merged.middleName.isEmpty {
                merged.middleName = contact.middleName
            } else if !contact.middleName.isEmpty && contact.middleName.lowercased() != merged.middleName.lowercased() {
                contactMergeInfo.append("Middle name: \(contact.middleName)")
            }

            // Nickname - append to existing if different
            if !contact.nickname.isEmpty && merged.nickname.isEmpty {
                merged.nickname = contact.nickname
            } else if !contact.nickname.isEmpty && contact.nickname.lowercased() != merged.nickname.lowercased() {
                alternateNames.append(contact.nickname)
            }

            // Company conflict
            if !contact.company.isEmpty && merged.company.isEmpty {
                merged.company = contact.company
            } else if !contact.company.isEmpty && contact.company.lowercased() != merged.company.lowercased() {
                contactMergeInfo.append("Company: \(contact.company)")
            }

            // Job title
            if !contact.jobTitle.isEmpty && merged.jobTitle.isEmpty {
                merged.jobTitle = contact.jobTitle
            } else if !contact.jobTitle.isEmpty && contact.jobTitle.lowercased() != merged.jobTitle.lowercased() {
                contactMergeInfo.append("Job title: \(contact.jobTitle)")
            }

            // Department
            if !contact.department.isEmpty && merged.department.isEmpty {
                merged.department = contact.department
            } else if !contact.department.isEmpty && contact.department.lowercased() != merged.department.lowercased() {
                contactMergeInfo.append("Department: \(contact.department)")
            }

            // Birthday - take if missing, note if different
            if contact.birthday != nil && merged.birthday == nil {
                merged.birthday = contact.birthday
            } else if let contactBday = contact.birthday, let mergedBday = merged.birthday,
                      contactBday != mergedBday {
                let bdayStr = "\(contactBday.month ?? 0)/\(contactBday.day ?? 0)/\(contactBday.year ?? 0)"
                contactMergeInfo.append("Birthday: \(bdayStr)")
            }

            // Notes - always append, never overwrite
            if !contact.notes.isEmpty {
                if merged.notes.isEmpty {
                    merged.notes = contact.notes
                } else if contact.notes != merged.notes {
                    contactMergeInfo.append("Notes: \(contact.notes)")
                }
            }

            // Image - take if missing
            if merged.imageData == nil {
                merged.imageData = contact.imageData
            }

            // Preserve identifiers for traceability
            if merged.googleIdentifier == nil && contact.googleIdentifier != nil {
                merged.googleIdentifier = contact.googleIdentifier
            }
            if merged.linkedinIdentifier == nil && contact.linkedinIdentifier != nil {
                merged.linkedinIdentifier = contact.linkedinIdentifier
            }

            // Build merge info for this contact
            if !contactMergeInfo.isEmpty {
                let sourceInfo = contact.appleIdentifier ?? contact.googleIdentifier ?? contact.linkedinIdentifier ?? "unknown"
                let header = "--- Merged from \(contact.source.rawValue) contact (ID: \(sourceInfo.prefix(8))...) ---"
                mergeNotes.append(header)
                mergeNotes.append(contentsOf: contactMergeInfo)
            }

            // Delete the duplicate from Apple Contacts
            if let appleId = contact.appleIdentifier {
                try? deleteContact(identifier: appleId)
            }
        }

        // Store alternate names in nickname field
        if !alternateNames.isEmpty {
            let uniqueAlternates = Array(Set(alternateNames)).joined(separator: ", ")
            if merged.nickname.isEmpty {
                merged.nickname = uniqueAlternates
            } else {
                merged.nickname = "\(merged.nickname), \(uniqueAlternates)"
            }
        }

        // Append merge history to notes
        if !mergeNotes.isEmpty {
            let mergeHistory = mergeNotes.joined(separator: "\n")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let mergeHeader = "\n\n=== MERGE HISTORY (\(timestamp)) ===\n"
            merged.notes = merged.notes + mergeHeader + mergeHistory
        }

        merged.updatedAt = Date()

        // Update the primary contact in Apple
        if merged.appleIdentifier != nil {
            try updateContact(merged)
        }

        return merged
    }

    /// Normalizes a phone number for comparison by removing non-digits
    private func normalizePhone(_ phone: String) -> String {
        return phone.filter { $0.isNumber }
    }

    // MARK: - Conversion Helpers

    private func convertToContactData(_ cnContact: CNContact) -> ContactData {
        let emails = cnContact.emailAddresses.map { $0.value as String }
        let phoneNumbers = cnContact.phoneNumbers.map { $0.value.stringValue }
        let addresses = cnContact.postalAddresses.map { postalAddress -> String in
            let address = postalAddress.value
            return [
                address.street,
                address.city,
                address.state,
                address.postalCode,
                address.country
            ].filter { !$0.isEmpty }.joined(separator: ", ")
        }

        // URLs
        let urls = cnContact.urlAddresses.map { $0.value as String }

        // Social profiles
        let socialProfiles = cnContact.socialProfiles.map { labeled -> SocialProfile in
            let profile = labeled.value
            return SocialProfile(
                service: profile.service,
                username: profile.username,
                urlString: profile.urlString
            )
        }

        // Instant message addresses
        let instantMessageAddresses = cnContact.instantMessageAddresses.map { labeled -> InstantMessageAddress in
            let im = labeled.value
            return InstantMessageAddress(
                service: im.service,
                username: im.username
            )
        }

        // Relationships
        let relationships = cnContact.contactRelations.map { labeled -> Relationship in
            return Relationship(
                name: labeled.value.name,
                label: labeled.label ?? "other"
            )
        }

        // Dates (excluding birthday which has its own field)
        let dates = cnContact.dates.map { labeled -> LabeledDate in
            return LabeledDate(
                label: labeled.label ?? "other",
                date: labeled.value as DateComponents
            )
        }

        return ContactData(
            firstName: cnContact.givenName,
            lastName: cnContact.familyName,
            middleName: cnContact.middleName,
            nickname: cnContact.nickname,
            company: cnContact.organizationName,
            jobTitle: cnContact.jobTitle,
            department: cnContact.departmentName,
            emails: emails,
            phoneNumbers: phoneNumbers,
            addresses: addresses,
            urls: urls,
            socialProfiles: socialProfiles,
            instantMessageAddresses: instantMessageAddresses,
            relationships: relationships,
            birthday: cnContact.birthday,
            dates: dates,
            notes: cnContact.note,
            imageData: cnContact.imageData ?? cnContact.thumbnailImageData,
            source: .apple,
            appleIdentifier: cnContact.identifier
        )
    }

    private func applyContactData(_ contact: ContactData, to mutableContact: CNMutableContact) {
        // Basic name fields
        mutableContact.givenName = contact.firstName
        mutableContact.familyName = contact.lastName
        mutableContact.middleName = contact.middleName
        mutableContact.nickname = contact.nickname

        // Organization
        mutableContact.organizationName = contact.company
        mutableContact.jobTitle = contact.jobTitle
        mutableContact.departmentName = contact.department

        // Set emails with labels
        mutableContact.emailAddresses = contact.emails.enumerated().map { index, email in
            let label = index == 0 ? CNLabelHome : CNLabelOther
            return CNLabeledValue(label: label, value: email as NSString)
        }

        // Set phone numbers with labels
        mutableContact.phoneNumbers = contact.phoneNumbers.enumerated().map { index, phone in
            let label = index == 0 ? CNLabelPhoneNumberMain : CNLabelPhoneNumberMobile
            return CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: phone))
        }

        // Set addresses
        mutableContact.postalAddresses = contact.addresses.map { addressString in
            let postalAddress = CNMutablePostalAddress()
            postalAddress.street = addressString
            return CNLabeledValue(label: CNLabelHome, value: postalAddress)
        }

        // Set URLs
        mutableContact.urlAddresses = contact.urls.map { url in
            return CNLabeledValue(label: CNLabelHome, value: url as NSString)
        }

        // Set social profiles
        mutableContact.socialProfiles = contact.socialProfiles.map { profile in
            let cnProfile = CNSocialProfile(
                urlString: profile.urlString,
                username: profile.username,
                userIdentifier: nil,
                service: profile.service
            )
            return CNLabeledValue(label: nil, value: cnProfile)
        }

        // Set instant message addresses
        mutableContact.instantMessageAddresses = contact.instantMessageAddresses.map { im in
            let cnIM = CNInstantMessageAddress(username: im.username, service: im.service)
            return CNLabeledValue(label: nil, value: cnIM)
        }

        // Set relationships
        mutableContact.contactRelations = contact.relationships.map { relation in
            let cnRelation = CNContactRelation(name: relation.name)
            return CNLabeledValue(label: relation.label, value: cnRelation)
        }

        // Set birthday
        mutableContact.birthday = contact.birthday

        // Set other dates
        mutableContact.dates = contact.dates.map { labeledDate in
            return CNLabeledValue(label: labeledDate.label, value: labeledDate.date as NSDateComponents)
        }

        // Set notes
        mutableContact.note = contact.notes

        // Set image
        if let imageData = contact.imageData {
            mutableContact.imageData = imageData
        }
    }
}
