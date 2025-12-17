import Foundation

@MainActor
class GoogleContactsImporter {
    private let authManager = GoogleAuthManager.shared
    private let appleManager = AppleContactsManager.shared
    private let duplicateDetector = DuplicateDetector()

    struct GoogleContact: Codable {
        let resourceName: String
        let names: [GoogleName]?
        let emailAddresses: [GoogleEmail]?
        let phoneNumbers: [GooglePhone]?
        let addresses: [GoogleAddress]?
        let organizations: [GoogleOrganization]?
        let photos: [GooglePhoto]?
        let biographies: [GoogleBiography]?
    }

    struct GoogleName: Codable {
        let givenName: String?
        let familyName: String?
        let displayName: String?
    }

    struct GoogleEmail: Codable {
        let value: String?
    }

    struct GooglePhone: Codable {
        let value: String?
    }

    struct GoogleAddress: Codable {
        let formattedValue: String?
        let streetAddress: String?
        let city: String?
        let region: String?
        let postalCode: String?
        let country: String?
    }

    struct GoogleOrganization: Codable {
        let name: String?
        let title: String?
    }

    struct GooglePhoto: Codable {
        let url: String?
    }

    struct GoogleBiography: Codable {
        let value: String?
    }

    struct GoogleContactsResponse: Codable {
        let connections: [GoogleContact]?
        let nextPageToken: String?
        let totalPeople: Int?
    }

    struct ImportResult {
        var imported: Int = 0
        var merged: Int = 0
        var skipped: Int = 0
        var errors: [String] = []
    }

    enum ImportError: Error, LocalizedError {
        case notAuthenticated
        case fetchFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Please sign in to Google first."
            case .fetchFailed(let message):
                return "Failed to fetch Google contacts: \(message)"
            case .invalidResponse:
                return "Received invalid response from Google."
            }
        }
    }

    // MARK: - Import with Deduplication

    func importWithDeduplication(
        existingContacts: [ContactData],
        similarityThreshold: Double = 0.7,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> ImportResult {
        let googleContacts = try await fetchAllContacts()
        return try await importContacts(googleContacts, existingContacts: existingContacts, progressHandler: progressHandler)
    }

    func importWithDeduplication(
        from account: GoogleAccount,
        existingContacts: [ContactData],
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> ImportResult {
        let googleContacts = try await fetchAllContacts(for: account)
        return try await importContacts(googleContacts, existingContacts: existingContacts, progressHandler: progressHandler)
    }

    private func importContacts(
        _ googleContacts: [ContactData],
        existingContacts: [ContactData],
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> ImportResult {
        var result = ImportResult()
        let total = googleContacts.count

        // Build indexes for fast lookup
        let emailIndex = buildEmailIndex(existingContacts)
        let phoneIndex = buildPhoneIndex(existingContacts)
        let nameIndex = buildNameIndex(existingContacts)
        let contactsById = Dictionary(uniqueKeysWithValues: existingContacts.map { ($0.id, $0) })

        for (index, googleContact) in googleContacts.enumerated() {
            progressHandler?(index + 1, total)

            // Skip contacts with no email AND no phone (incomplete)
            if googleContact.emails.isEmpty && googleContact.phoneNumbers.isEmpty {
                result.skipped += 1
                continue
            }

            // Check for existing duplicate using strict matching (exact email, phone, or name)
            if let existingMatch = findExactMatch(for: googleContact, emailIndex: emailIndex, phoneIndex: phoneIndex, nameIndex: nameIndex, contactsById: contactsById) {
                // Merge into existing contact
                let merged = mergeContacts(existing: existingMatch, incoming: googleContact)
                do {
                    try appleManager.updateContact(merged)
                    result.merged += 1
                } catch {
                    result.errors.append("Failed to merge \(googleContact.displayName): \(error.localizedDescription)")
                }
            } else {
                // Import as new contact to Apple
                do {
                    try appleManager.createContact(googleContact)
                    result.imported += 1
                } catch {
                    result.errors.append("Failed to import \(googleContact.displayName): \(error.localizedDescription)")
                }
            }
        }

        return result
    }

    private func findExactMatch(
        for contact: ContactData,
        emailIndex: [String: UUID],
        phoneIndex: [String: UUID],
        nameIndex: [String: UUID],
        contactsById: [UUID: ContactData]
    ) -> ContactData? {
        // Check for exact email match
        for email in contact.emails {
            let normalized = email.lowercased()
            if let matchId = emailIndex[normalized], let match = contactsById[matchId] {
                return match
            }
        }

        // Check for exact phone match (last 7 digits)
        for phone in contact.phoneNumbers {
            let normalized = phone.filter { $0.isNumber }
            if normalized.count >= 7 {
                let suffix = String(normalized.suffix(7))
                if let matchId = phoneIndex[suffix], let match = contactsById[matchId] {
                    return match
                }
            }
        }

        // Check for exact name match (case-insensitive)
        let nameKey = normalizeNameKey(firstName: contact.firstName, lastName: contact.lastName)
        if !nameKey.isEmpty, let matchId = nameIndex[nameKey], let match = contactsById[matchId] {
            return match
        }

        return nil
    }

    private func normalizeNameKey(firstName: String, lastName: String) -> String {
        let first = firstName.lowercased().trimmingCharacters(in: .whitespaces)
        let last = lastName.lowercased().trimmingCharacters(in: .whitespaces)
        guard !first.isEmpty && !last.isEmpty else { return "" }
        return "\(first)|\(last)"
    }

    private func buildNameIndex(_ contacts: [ContactData]) -> [String: UUID] {
        var index: [String: UUID] = [:]
        for contact in contacts {
            let key = normalizeNameKey(firstName: contact.firstName, lastName: contact.lastName)
            if !key.isEmpty {
                index[key] = contact.id
            }
        }
        return index
    }

    private func buildEmailIndex(_ contacts: [ContactData]) -> [String: UUID] {
        var index: [String: UUID] = [:]
        for contact in contacts {
            for email in contact.emails {
                index[email.lowercased()] = contact.id
            }
        }
        return index
    }

    private func buildPhoneIndex(_ contacts: [ContactData]) -> [String: UUID] {
        var index: [String: UUID] = [:]
        for contact in contacts {
            for phone in contact.phoneNumbers {
                let normalized = phone.filter { $0.isNumber }
                if normalized.count >= 7 {
                    let suffix = String(normalized.suffix(7))
                    index[suffix] = contact.id
                }
            }
        }
        return index
    }

    private func mergeContacts(existing: ContactData, incoming: ContactData) -> ContactData {
        var merged = existing

        // Add unique emails
        let newEmails = incoming.emails.filter { email in
            !existing.emails.contains { $0.lowercased() == email.lowercased() }
        }
        merged.emails.append(contentsOf: newEmails)

        // Add unique phone numbers (normalize for comparison)
        let normalizedExistingPhones = Set(existing.phoneNumbers.map { normalizePhone($0) })
        let newPhones = incoming.phoneNumbers.filter { phone in
            !normalizedExistingPhones.contains(normalizePhone(phone))
        }
        merged.phoneNumbers.append(contentsOf: newPhones)

        // Add unique addresses
        let newAddresses = incoming.addresses.filter { !existing.addresses.contains($0) }
        merged.addresses.append(contentsOf: newAddresses)

        // Fill in missing fields
        if merged.firstName.isEmpty { merged.firstName = incoming.firstName }
        if merged.lastName.isEmpty { merged.lastName = incoming.lastName }
        if merged.company.isEmpty { merged.company = incoming.company }
        if merged.notes.isEmpty { merged.notes = incoming.notes }
        if merged.imageData == nil { merged.imageData = incoming.imageData }

        // Store Google identifier
        merged.googleIdentifier = incoming.googleIdentifier

        return merged
    }

    private func normalizePhone(_ phone: String) -> String {
        return phone.filter { $0.isNumber }
    }

    // MARK: - Fetch Operations

    func fetchAllContacts() async throws -> [ContactData] {
        guard let accessToken = authManager.accessToken else {
            throw ImportError.notAuthenticated
        }
        return try await fetchAllContacts(accessToken: accessToken, email: authManager.userEmail)
    }

    func fetchAllContacts(for account: GoogleAccount) async throws -> [ContactData] {
        // Ensure this account is current and get a fresh token
        let freshToken = try await authManager.ensureCurrentAndGetToken(for: account.email)
        return try await fetchAllContacts(accessToken: freshToken, email: account.email)
    }

    private func fetchAllContacts(accessToken: String, email: String?) async throws -> [ContactData] {
        var allContacts: [ContactData] = []
        var pageToken: String?

        repeat {
            var urlString = "https://people.googleapis.com/v1/people/me/connections"
            urlString += "?personFields=names,emailAddresses,phoneNumbers,addresses,organizations,photos,biographies"
            urlString += "&pageSize=100"
            if let token = pageToken {
                urlString += "&pageToken=\(token)"
            }

            guard let url = URL(string: urlString) else {
                throw ImportError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ImportError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                // Try to refresh the token for this account
                if let email = email {
                    try await authManager.refreshToken(for: email)
                    if let newToken = authManager.getAccessToken(for: email) {
                        return try await fetchAllContacts(accessToken: newToken, email: email)
                    }
                }
                throw ImportError.notAuthenticated
            }

            guard httpResponse.statusCode == 200 else {
                throw ImportError.fetchFailed("HTTP \(httpResponse.statusCode)")
            }

            let decoder = JSONDecoder()
            let googleResponse = try decoder.decode(GoogleContactsResponse.self, from: data)

            if let connections = googleResponse.connections {
                let contacts = connections.map { convertToContactData($0) }
                allContacts.append(contentsOf: contacts)
            }

            pageToken = googleResponse.nextPageToken
        } while pageToken != nil

        return allContacts
    }

    private func convertToContactData(_ googleContact: GoogleContact) -> ContactData {
        let firstName = googleContact.names?.first?.givenName ?? ""
        let lastName = googleContact.names?.first?.familyName ?? ""
        let company = googleContact.organizations?.first?.name ?? ""

        let emails = googleContact.emailAddresses?.compactMap { $0.value } ?? []
        let phones = googleContact.phoneNumbers?.compactMap { $0.value } ?? []

        let addresses: [String] = googleContact.addresses?.compactMap { address -> String? in
            if let formatted = address.formattedValue, !formatted.isEmpty {
                return formatted
            }
            let parts = [
                address.streetAddress,
                address.city,
                address.region,
                address.postalCode,
                address.country
            ].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        } ?? []

        let notes = googleContact.biographies?.first?.value ?? ""

        let resourceId = googleContact.resourceName.replacingOccurrences(of: "people/", with: "")

        return ContactData(
            firstName: firstName,
            lastName: lastName,
            company: company,
            emails: emails,
            phoneNumbers: phones,
            addresses: addresses,
            notes: notes,
            imageData: nil,
            source: .google,
            googleIdentifier: resourceId
        )
    }

    func downloadPhoto(url: String) async -> Data? {
        guard let photoURL = URL(string: url),
              let accessToken = authManager.accessToken else {
            return nil
        }

        var request = URLRequest(url: photoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        } catch {
            return nil
        }
    }
}
