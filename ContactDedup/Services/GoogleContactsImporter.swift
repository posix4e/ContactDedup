import Foundation

@MainActor
class GoogleContactsImporter {
    private let authManager = GoogleAuthManager.shared
    private let appleManager = AppleContactsManager.shared
    private let duplicateDetector = DuplicateDetector()

    struct GoogleContact: Codable {
        let resourceName: String
        let names: [GoogleName]?
        let nicknames: [GoogleNickname]?
        let emailAddresses: [GoogleEmail]?
        let phoneNumbers: [GooglePhone]?
        let addresses: [GoogleAddress]?
        let organizations: [GoogleOrganization]?
        let photos: [GooglePhoto]?
        let biographies: [GoogleBiography]?
        let urls: [GoogleUrl]?
        let relations: [GoogleRelation]?
        let birthdays: [GoogleBirthday]?
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
        let department: String?
    }

    struct GooglePhoto: Codable {
        let url: String?
    }

    struct GoogleBiography: Codable {
        let value: String?
    }

    struct GoogleNickname: Codable {
        let value: String?
    }

    struct GoogleUrl: Codable {
        let value: String?
    }

    struct GoogleRelation: Codable {
        let person: String?
        let type: String?
    }

    struct GoogleBirthday: Codable {
        let date: GoogleDate?
    }

    struct GoogleDate: Codable {
        let year: Int?
        let month: Int?
        let day: Int?
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
        return try await importContacts(
            googleContacts,
            existingContacts: existingContacts,
            progressHandler: progressHandler
        )
    }

    func importWithDeduplication(
        from account: GoogleAccount,
        existingContacts: [ContactData],
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> ImportResult {
        let googleContacts = try await fetchAllContacts(for: account)
        return try await importContacts(
            googleContacts,
            existingContacts: existingContacts,
            progressHandler: progressHandler
        )
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
            let existingMatch = findExactMatch(
                for: googleContact,
                emailIndex: emailIndex,
                phoneIndex: phoneIndex,
                nameIndex: nameIndex,
                contactsById: contactsById
            )
            if let existingMatch {
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
        emailIndex: [String: Set<UUID>],
        phoneIndex: [String: Set<UUID>],
        nameIndex: [String: Set<UUID>],
        contactsById: [UUID: ContactData]
    ) -> ContactData? {
        // Check for exact email match - return first match from any matching contact
        for email in contact.emails {
            let normalized = email.lowercased()
            if let matchIds = emailIndex[normalized], let matchId = matchIds.first,
               let match = contactsById[matchId] {
                return match
            }
        }

        // Check for exact phone match (last 7 digits)
        for phone in contact.phoneNumbers {
            let normalized = phone.filter { $0.isNumber }
            if normalized.count >= 7 {
                let suffix = String(normalized.suffix(7))
                if let matchIds = phoneIndex[suffix], let matchId = matchIds.first,
                   let match = contactsById[matchId] {
                    return match
                }
            }
        }

        // Check for exact name match (case-insensitive)
        let nameKey = normalizeNameKey(firstName: contact.firstName, lastName: contact.lastName)
        if !nameKey.isEmpty, let matchIds = nameIndex[nameKey], let matchId = matchIds.first,
           let match = contactsById[matchId] {
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

    private func buildNameIndex(_ contacts: [ContactData]) -> [String: Set<UUID>] {
        var index: [String: Set<UUID>] = [:]
        for contact in contacts {
            let key = normalizeNameKey(firstName: contact.firstName, lastName: contact.lastName)
            if !key.isEmpty {
                index[key, default: []].insert(contact.id)
            }
        }
        return index
    }

    private func buildEmailIndex(_ contacts: [ContactData]) -> [String: Set<UUID>] {
        var index: [String: Set<UUID>] = [:]
        for contact in contacts {
            for email in contact.emails {
                index[email.lowercased(), default: []].insert(contact.id)
            }
        }
        return index
    }

    private func buildPhoneIndex(_ contacts: [ContactData]) -> [String: Set<UUID>] {
        var index: [String: Set<UUID>] = [:]
        for contact in contacts {
            for phone in contact.phoneNumbers {
                let normalized = phone.filter { $0.isNumber }
                if normalized.count >= 7 {
                    let suffix = String(normalized.suffix(7))
                    index[suffix, default: []].insert(contact.id)
                }
            }
        }
        return index
    }

    /// Lossless merge - preserves all data from both contacts, storing conflicts in notes
    private func mergeContacts(existing: ContactData, incoming: ContactData) -> ContactData {
        var merged = existing
        var mergeInfo: [String] = []
        var alternateNames: [String] = []

        // === ADDITIVE MERGES (no data loss) ===

        // Add unique emails (case-insensitive)
        let existingEmailsLower = Set(existing.emails.map { $0.lowercased() })
        let newEmails = incoming.emails.filter { !existingEmailsLower.contains($0.lowercased()) }
        merged.emails.append(contentsOf: newEmails)

        // Add unique phone numbers (normalize for comparison)
        let normalizedExistingPhones = Set(existing.phoneNumbers.map { normalizePhone($0) })
        let newPhones = incoming.phoneNumbers.filter { !normalizedExistingPhones.contains(normalizePhone($0)) }
        merged.phoneNumbers.append(contentsOf: newPhones)

        // Add unique addresses
        let newAddresses = incoming.addresses.filter { !existing.addresses.contains($0) }
        merged.addresses.append(contentsOf: newAddresses)

        // Add unique URLs
        let existingUrlsLower = Set(existing.urls.map { $0.lowercased() })
        let newUrls = incoming.urls.filter { !existingUrlsLower.contains($0.lowercased()) }
        merged.urls.append(contentsOf: newUrls)

        // Add unique social profiles
        let existingProfiles = Set(merged.socialProfiles.map { "\($0.service.lowercased()):\($0.username.lowercased())" })
        let newProfiles = incoming.socialProfiles.filter {
            !existingProfiles.contains("\($0.service.lowercased()):\($0.username.lowercased())")
        }
        merged.socialProfiles.append(contentsOf: newProfiles)

        // Add unique relationships
        let existingRelations = Set(merged.relationships.map { "\($0.label.lowercased()):\($0.name.lowercased())" })
        let newRelations = incoming.relationships.filter {
            !existingRelations.contains("\($0.label.lowercased()):\($0.name.lowercased())")
        }
        merged.relationships.append(contentsOf: newRelations)

        // Add unique dates
        let existingDates = Set(merged.dates.map { "\($0.label):\($0.date.month ?? 0)-\($0.date.day ?? 0)" })
        let newDates = incoming.dates.filter {
            !existingDates.contains("\($0.label):\($0.date.month ?? 0)-\($0.date.day ?? 0)")
        }
        merged.dates.append(contentsOf: newDates)

        // === CONFLICT-AWARE MERGES (preserve conflicts in notes) ===

        // Handle name conflicts - preserve alternate names
        let incomingFullName = "\(incoming.firstName) \(incoming.lastName)".trimmingCharacters(in: .whitespaces)
        let existingFullName = "\(existing.firstName) \(existing.lastName)".trimmingCharacters(in: .whitespaces)
        if !incomingFullName.isEmpty && incomingFullName.lowercased() != existingFullName.lowercased() {
            alternateNames.append(incomingFullName)
        }

        // First name
        if !incoming.firstName.isEmpty && merged.firstName.isEmpty {
            merged.firstName = incoming.firstName
        } else if !incoming.firstName.isEmpty && incoming.firstName.lowercased() != merged.firstName.lowercased() {
            mergeInfo.append("First name: \(incoming.firstName)")
        }

        // Last name
        if !incoming.lastName.isEmpty && merged.lastName.isEmpty {
            merged.lastName = incoming.lastName
        } else if !incoming.lastName.isEmpty && incoming.lastName.lowercased() != merged.lastName.lowercased() {
            mergeInfo.append("Last name: \(incoming.lastName)")
        }

        // Middle name
        if !incoming.middleName.isEmpty && merged.middleName.isEmpty {
            merged.middleName = incoming.middleName
        } else if !incoming.middleName.isEmpty && incoming.middleName.lowercased() != merged.middleName.lowercased() {
            mergeInfo.append("Middle name: \(incoming.middleName)")
        }

        // Nickname
        if !incoming.nickname.isEmpty && merged.nickname.isEmpty {
            merged.nickname = incoming.nickname
        } else if !incoming.nickname.isEmpty && incoming.nickname.lowercased() != merged.nickname.lowercased() {
            alternateNames.append(incoming.nickname)
        }

        // Company
        if !incoming.company.isEmpty && merged.company.isEmpty {
            merged.company = incoming.company
        } else if !incoming.company.isEmpty && incoming.company.lowercased() != merged.company.lowercased() {
            mergeInfo.append("Company: \(incoming.company)")
        }

        // Job title
        if !incoming.jobTitle.isEmpty && merged.jobTitle.isEmpty {
            merged.jobTitle = incoming.jobTitle
        } else if !incoming.jobTitle.isEmpty && incoming.jobTitle.lowercased() != merged.jobTitle.lowercased() {
            mergeInfo.append("Job title: \(incoming.jobTitle)")
        }

        // Department
        if !incoming.department.isEmpty && merged.department.isEmpty {
            merged.department = incoming.department
        } else if !incoming.department.isEmpty && incoming.department.lowercased() != merged.department.lowercased() {
            mergeInfo.append("Department: \(incoming.department)")
        }

        // Birthday
        if incoming.birthday != nil && merged.birthday == nil {
            merged.birthday = incoming.birthday
        } else if let incomingBday = incoming.birthday, let existingBday = merged.birthday,
                  incomingBday != existingBday {
            let bdayStr = "\(incomingBday.month ?? 0)/\(incomingBday.day ?? 0)/\(incomingBday.year ?? 0)"
            mergeInfo.append("Birthday: \(bdayStr)")
        }

        // Notes - always append, never overwrite
        if !incoming.notes.isEmpty {
            if merged.notes.isEmpty {
                merged.notes = incoming.notes
            } else if incoming.notes != merged.notes {
                mergeInfo.append("Notes: \(incoming.notes)")
            }
        }

        // Image - take if missing
        if merged.imageData == nil {
            merged.imageData = incoming.imageData
        }

        // Store Google identifier
        merged.googleIdentifier = incoming.googleIdentifier

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
        if !mergeInfo.isEmpty {
            let mergeHistory = mergeInfo.joined(separator: "\n")
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let header = "\n\n=== MERGED FROM GOOGLE (\(timestamp)) ===\n"
            merged.notes = merged.notes + header + mergeHistory
        }

        merged.updatedAt = Date()
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
            urlString += "?personFields=names,nicknames,emailAddresses,phoneNumbers,addresses,organizations,photos,biographies,urls,relations,birthdays"
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
        let nickname = googleContact.nicknames?.first?.value ?? ""
        let company = googleContact.organizations?.first?.name ?? ""
        let jobTitle = googleContact.organizations?.first?.title ?? ""
        let department = googleContact.organizations?.first?.department ?? ""

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

        let urls = googleContact.urls?.compactMap { $0.value } ?? []

        // Convert relationships
        let relationships: [Relationship] = googleContact.relations?.compactMap { relation -> Relationship? in
            guard let name = relation.person else { return nil }
            return Relationship(name: name, label: relation.type ?? "other")
        } ?? []

        // Convert birthday
        var birthday: DateComponents?
        if let googleBday = googleContact.birthdays?.first?.date {
            var components = DateComponents()
            components.year = googleBday.year
            components.month = googleBday.month
            components.day = googleBday.day
            birthday = components
        }

        let notes = googleContact.biographies?.first?.value ?? ""

        let resourceId = googleContact.resourceName.replacingOccurrences(of: "people/", with: "")

        return ContactData(
            firstName: firstName,
            lastName: lastName,
            nickname: nickname,
            company: company,
            jobTitle: jobTitle,
            department: department,
            emails: emails,
            phoneNumbers: phones,
            addresses: addresses,
            urls: urls,
            relationships: relationships,
            birthday: birthday,
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
