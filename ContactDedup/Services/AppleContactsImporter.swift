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
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
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

    func mergeContacts(_ contacts: [ContactData], into primary: ContactData) throws -> ContactData {
        var merged = primary

        for contact in contacts where contact.id != primary.id {
            // Merge emails (add unique ones)
            let newEmails = contact.emails.filter { !merged.emails.contains($0) }
            merged.emails.append(contentsOf: newEmails)

            // Merge phone numbers (add unique ones)
            let newPhones = contact.phoneNumbers.filter { !merged.phoneNumbers.contains($0) }
            merged.phoneNumbers.append(contentsOf: newPhones)

            // Merge addresses (add unique ones)
            let newAddresses = contact.addresses.filter { !merged.addresses.contains($0) }
            merged.addresses.append(contentsOf: newAddresses)

            // Fill in missing fields
            if merged.firstName.isEmpty { merged.firstName = contact.firstName }
            if merged.lastName.isEmpty { merged.lastName = contact.lastName }
            if merged.company.isEmpty { merged.company = contact.company }
            if merged.notes.isEmpty { merged.notes = contact.notes }
            if merged.imageData == nil { merged.imageData = contact.imageData }

            // Delete the duplicate from Apple Contacts
            if let appleId = contact.appleIdentifier {
                try? deleteContact(identifier: appleId)
            }
        }

        // Update the primary contact in Apple
        if merged.appleIdentifier != nil {
            try updateContact(merged)
        }

        return merged
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

        return ContactData(
            firstName: cnContact.givenName,
            lastName: cnContact.familyName,
            company: cnContact.organizationName,
            emails: emails,
            phoneNumbers: phoneNumbers,
            addresses: addresses,
            notes: "",
            imageData: cnContact.imageData ?? cnContact.thumbnailImageData,
            source: .apple,
            appleIdentifier: cnContact.identifier
        )
    }

    private func applyContactData(_ contact: ContactData, to mutableContact: CNMutableContact) {
        mutableContact.givenName = contact.firstName
        mutableContact.familyName = contact.lastName
        mutableContact.organizationName = contact.company

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

        if let imageData = contact.imageData {
            mutableContact.imageData = imageData
        }
    }
}
