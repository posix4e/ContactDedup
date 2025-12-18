import Foundation

class DuplicateDetector {
    private let similarityEngine = SimilarityEngine.shared

    // Weights for different fields
    struct SimilarityWeights {
        var name: Double = 0.35
        var email: Double = 0.30
        var phone: Double = 0.25
        var company: Double = 0.10

        static let `default` = SimilarityWeights()

        static let nameHeavy = SimilarityWeights(name: 0.50, email: 0.25, phone: 0.20, company: 0.05)
        static let emailHeavy = SimilarityWeights(name: 0.25, email: 0.45, phone: 0.20, company: 0.10)
    }

    var weights = SimilarityWeights.default
    var similarityThreshold: Double = 0.90

    // MARK: - Pre-computed Data for Fast Comparison

    private struct NormalizedContact {
        let id: UUID
        let firstName: String  // lowercased, trimmed
        let lastName: String   // lowercased, trimmed
        let normalizedPhones: Set<String>  // digits only
        let phoneSuffixes: Set<String>     // last 7 digits
        let normalizedEmails: Set<String>  // lowercased
        let company: String                // lowercased, trimmed
        let hasFullName: Bool
    }

    private func normalizeContacts(_ contacts: [ContactData]) -> [UUID: NormalizedContact] {
        var result: [UUID: NormalizedContact] = [:]
        result.reserveCapacity(contacts.count)

        for contact in contacts {
            let firstName = contact.firstName.trimmingCharacters(in: .whitespaces).lowercased()
            let lastName = contact.lastName.trimmingCharacters(in: .whitespaces).lowercased()

            var normalizedPhones = Set<String>()
            var phoneSuffixes = Set<String>()
            for phone in contact.phoneNumbers {
                let normalized = phone.filter { $0.isNumber }
                normalizedPhones.insert(normalized)
                if normalized.count >= 7 {
                    phoneSuffixes.insert(String(normalized.suffix(7)))
                }
            }

            let normalizedEmails = Set(contact.emails.map { $0.lowercased() })
            let company = contact.company.trimmingCharacters(in: .whitespaces).lowercased()

            result[contact.id] = NormalizedContact(
                id: contact.id,
                firstName: firstName,
                lastName: lastName,
                normalizedPhones: normalizedPhones,
                phoneSuffixes: phoneSuffixes,
                normalizedEmails: normalizedEmails,
                company: company,
                hasFullName: !firstName.isEmpty && !lastName.isEmpty
            )
        }
        return result
    }

    // MARK: - Main Detection

    func findDuplicateGroups(
        in contacts: [ContactData],
        progressHandler: ((Int, String) -> Void)? = nil
    ) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        var processedIds = Set<UUID>()

        // Pre-normalize all contacts once
        let normalizedContacts = normalizeContacts(contacts)
        let contactsById = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) })

        // Build indexes for quick candidate lookup
        let phoneIndex = buildPhoneIndex(contacts)
        let emailIndex = buildEmailIndex(contacts)
        let nameIndex = buildNameIndex(contacts)

        for (index, contact) in contacts.enumerated() {
            if processedIds.contains(contact.id) { continue }

            // Report progress every 100 contacts to reduce UI overhead
            if index % 100 == 0 {
                progressHandler?(index, contact.displayName)
            }

            guard let normalized = normalizedContacts[contact.id] else { continue }

            // Get candidate contacts from indexes instead of checking all
            var candidates = Set<UUID>()

            // Add candidates with matching phone suffixes
            for suffix in normalized.phoneSuffixes {
                if let matches = phoneIndex[suffix] {
                    candidates.formUnion(matches)
                }
            }

            // Add candidates with matching emails (exact match only for speed)
            for email in normalized.normalizedEmails {
                if let atIndex = email.firstIndex(of: "@") {
                    let local = String(email[..<atIndex])
                    if let matches = emailIndex[local] {
                        candidates.formUnion(matches)
                    }
                }
            }

            // Add candidates with similar name prefixes
            let nameKey = makeNameKey(contact)
            if !nameKey.isEmpty, let matches = nameIndex[nameKey] {
                candidates.formUnion(matches)
            }

            // Remove self and already processed
            candidates.remove(contact.id)
            candidates.subtract(processedIds)

            var group = [contact]
            var groupResults: [SimilarityResult] = []

            for candidateId in candidates {
                guard let other = contactsById[candidateId],
                      let otherNormalized = normalizedContacts[candidateId] else { continue }

                if let result = calculateDetailedSimilarityFast(
                    contact1: contact, normalized1: normalized,
                    contact2: other, normalized2: otherNormalized
                ) {
                    group.append(other)
                    groupResults.append(result)
                }
            }

            if group.count > 1, let firstResult = groupResults.first {
                let matchType: DuplicateMatchType
                switch firstResult.matchType {
                case .exactEmail: matchType = .exactEmail
                case .exactPhone: matchType = .exactPhone
                case .similar: matchType = .similar
                }

                var additionalScores: [String: Double] = [:]
                if firstResult.companySimilarity > 0 {
                    additionalScores["company"] = firstResult.companySimilarity
                }

                groups.append(DuplicateGroup(
                    contacts: group,
                    matchType: matchType,
                    nameSimilarity: firstResult.nameSimilarity,
                    additionalScores: additionalScores
                ))
                group.forEach { processedIds.insert($0.id) }
            }
        }

        return groups.sorted { $0.similarityScore > $1.similarityScore }
    }

    // MARK: - Indexing for Fast Lookup

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

    private func buildEmailIndex(_ contacts: [ContactData]) -> [String: Set<UUID>] {
        var index: [String: Set<UUID>] = [:]
        for contact in contacts {
            for email in contact.emails {
                let lower = email.lowercased()
                if let atIndex = lower.firstIndex(of: "@") {
                    let local = String(lower[..<atIndex])
                    let domain = String(lower[atIndex...])
                    index[local, default: []].insert(contact.id)
                    index[domain, default: []].insert(contact.id)
                }
            }
        }
        return index
    }

    private func buildNameIndex(_ contacts: [ContactData]) -> [String: Set<UUID>] {
        var index: [String: Set<UUID>] = [:]
        for contact in contacts {
            let key = makeNameKey(contact)
            if !key.isEmpty {
                index[key, default: []].insert(contact.id)
            }
        }
        return index
    }

    private func makeNameKey(_ contact: ContactData) -> String {
        // Use first 3 chars of first name + first 3 chars of last name as key
        let first = contact.firstName.lowercased().prefix(3)
        let last = contact.lastName.lowercased().prefix(3)
        return "\(first)\(last)"
    }

    func findPotentialDuplicates(
        for contact: ContactData,
        in contacts: [ContactData]
    ) -> [(contact: ContactData, score: Double)] {
        var duplicates: [(ContactData, Double)] = []

        for other in contacts {
            if other.id == contact.id { continue }

            let score = calculateSimilarity(contact1: contact, contact2: other)
            if score >= similarityThreshold {
                duplicates.append((other, score))
            }
        }

        return duplicates.sorted { $0.1 > $1.1 }
    }

    // MARK: - Similarity Calculation

    struct SimilarityResult {
        let matchType: MatchType
        let nameSimilarity: Double
        let emailSimilarity: Double
        let phoneSimilarity: Double
        let companySimilarity: Double

        enum MatchType: String {
            case exactEmail = "Same Email"
            case exactPhone = "Same Phone"
            case similar = "Similar"
        }

        var overallScore: Double {
            switch matchType {
            case .exactEmail, .exactPhone:
                return 1.0
            case .similar:
                // Weighted average of other fields
                var total = nameSimilarity * 0.5
                total += companySimilarity * 0.5
                return total
            }
        }
    }

    /// Fast similarity calculation using pre-normalized data
    private func calculateDetailedSimilarityFast(
        contact1: ContactData, normalized1: NormalizedContact,
        contact2: ContactData, normalized2: NormalizedContact
    ) -> SimilarityResult? {
        // Check exact email match first (fastest check using Sets)
        let emailIntersection = normalized1.normalizedEmails.intersection(normalized2.normalizedEmails)
        if !emailIntersection.isEmpty {
            let namesMatch = normalized1.firstName == normalized2.firstName
                && normalized1.lastName == normalized2.lastName
            return SimilarityResult(
                matchType: .exactEmail,
                nameSimilarity: namesMatch ? 1.0 : 0.5,
                emailSimilarity: 1.0,
                phoneSimilarity: 0.0,
                companySimilarity: normalized1.company == normalized2.company ? 1.0 : 0.0
            )
        }

        // Check exact phone match (using normalized phone numbers)
        let phoneIntersection = normalized1.normalizedPhones.intersection(normalized2.normalizedPhones)
        if !phoneIntersection.isEmpty {
            let namesMatch = normalized1.firstName == normalized2.firstName
                && normalized1.lastName == normalized2.lastName
            return SimilarityResult(
                matchType: .exactPhone,
                nameSimilarity: namesMatch ? 1.0 : 0.5,
                emailSimilarity: 0.0,
                phoneSimilarity: 1.0,
                companySimilarity: normalized1.company == normalized2.company ? 1.0 : 0.0
            )
        }

        // Check phone suffix match (last 7 digits)
        let suffixIntersection = normalized1.phoneSuffixes.intersection(normalized2.phoneSuffixes)
        if !suffixIntersection.isEmpty {
            let namesMatch = normalized1.firstName == normalized2.firstName
                && normalized1.lastName == normalized2.lastName
            return SimilarityResult(
                matchType: .exactPhone,
                nameSimilarity: namesMatch ? 1.0 : 0.5,
                emailSimilarity: 0.0,
                phoneSimilarity: 0.95,
                companySimilarity: normalized1.company == normalized2.company ? 1.0 : 0.0
            )
        }

        // For name-only matching, both must have full names
        guard normalized1.hasFullName && normalized2.hasFullName else {
            return nil
        }

        // Check for exact name match (using pre-lowercased strings)
        if normalized1.firstName == normalized2.firstName && normalized1.lastName == normalized2.lastName {
            return SimilarityResult(
                matchType: .similar,
                nameSimilarity: 1.0,
                emailSimilarity: 0.0,
                phoneSimilarity: 0.0,
                companySimilarity: normalized1.company == normalized2.company ? 1.0 : 0.0
            )
        }

        // Only do expensive Jaro-Winkler if names are close enough
        // Quick length check first - names with very different lengths can't be 95% similar
        let fn1Len = normalized1.firstName.count
        let fn2Len = normalized2.firstName.count
        let ln1Len = normalized1.lastName.count
        let ln2Len = normalized2.lastName.count

        // If length difference is too big, skip expensive comparison
        // For 95% Jaro-Winkler similarity, lengths should be within ~20% of each other
        let fnLenRatio = fn1Len > 0 && fn2Len > 0 ? Double(min(fn1Len, fn2Len)) / Double(max(fn1Len, fn2Len)) : 0
        let lnLenRatio = ln1Len > 0 && ln2Len > 0 ? Double(min(ln1Len, ln2Len)) / Double(max(ln1Len, ln2Len)) : 0

        if fnLenRatio < 0.7 || lnLenRatio < 0.7 {
            return nil
        }

        // Now do the expensive Jaro-Winkler comparison
        let firstNameSim = similarityEngine.jaroWinklerSimilarity(normalized1.firstName, normalized2.firstName)
        let lastNameSim = similarityEngine.jaroWinklerSimilarity(normalized1.lastName, normalized2.lastName)

        if firstNameSim >= 0.95 && lastNameSim >= 0.95 {
            return SimilarityResult(
                matchType: .similar,
                nameSimilarity: (firstNameSim + lastNameSim) / 2,
                emailSimilarity: 0.0,
                phoneSimilarity: 0.0,
                companySimilarity: normalized1.company == normalized2.company ? 1.0 : 0.0
            )
        }

        return nil
    }

    func calculateDetailedSimilarity(contact1: ContactData, contact2: ContactData) -> SimilarityResult? {
        let nameSim = calculateNameSimilarity(contact1: contact1, contact2: contact2)
        let emailSim = calculateEmailSimilarity(contact1: contact1, contact2: contact2)
        let phoneSim = calculatePhoneSimilarity(contact1: contact1, contact2: contact2)
        let companySim = calculateCompanySimilarity(contact1: contact1, contact2: contact2)

        // Exact email match - definite duplicate
        if emailSim == 1.0 {
            return SimilarityResult(
                matchType: .exactEmail,
                nameSimilarity: nameSim,
                emailSimilarity: emailSim,
                phoneSimilarity: phoneSim,
                companySimilarity: companySim
            )
        }

        // Exact phone match - definite duplicate
        if phoneSim == 1.0 {
            return SimilarityResult(
                matchType: .exactPhone,
                nameSimilarity: nameSim,
                emailSimilarity: emailSim,
                phoneSimilarity: phoneSim,
                companySimilarity: companySim
            )
        }

        // For "similar" matches WITHOUT exact email/phone:
        // - Both contacts must have BOTH first AND last name (single names are not enough data)
        // - Require BOTH first name AND last name to be very similar (not just full name)
        // - This prevents matching "Mark Harrison" with "Margo Harrison" (family members)
        let firstName1 = contact1.firstName.trimmingCharacters(in: .whitespaces).lowercased()
        let lastName1 = contact1.lastName.trimmingCharacters(in: .whitespaces).lowercased()
        let firstName2 = contact2.firstName.trimmingCharacters(in: .whitespaces).lowercased()
        let lastName2 = contact2.lastName.trimmingCharacters(in: .whitespaces).lowercased()

        // Both contacts must have first AND last name for name-only matching
        let hasBothNames1 = !firstName1.isEmpty && !lastName1.isEmpty
        let hasBothNames2 = !firstName2.isEmpty && !lastName2.isEmpty

        guard hasBothNames1 && hasBothNames2 else {
            return nil  // Not enough name data to compare
        }

        // Check for exact name match
        let isExactFirstName = firstName1 == firstName2
        let isExactLastName = lastName1 == lastName2

        if isExactFirstName && isExactLastName {
            return SimilarityResult(
                matchType: .similar,
                nameSimilarity: 1.0,
                emailSimilarity: emailSim,
                phoneSimilarity: phoneSim,
                companySimilarity: companySim
            )
        }

        // For non-exact matches, require BOTH first and last name to be 95%+ similar
        // This catches typos like "John" vs "Jonh" but not "Mark" vs "Margo"
        let firstNameSim = similarityEngine.jaroWinklerSimilarity(firstName1, firstName2)
        let lastNameSim = similarityEngine.jaroWinklerSimilarity(lastName1, lastName2)

        if firstNameSim >= 0.95 && lastNameSim >= 0.95 {
            return SimilarityResult(
                matchType: .similar,
                nameSimilarity: (firstNameSim + lastNameSim) / 2,
                emailSimilarity: emailSim,
                phoneSimilarity: phoneSim,
                companySimilarity: companySim
            )
        }

        return nil  // Not a duplicate
    }

    func calculateSimilarity(contact1: ContactData, contact2: ContactData) -> Double {
        guard let result = calculateDetailedSimilarity(contact1: contact1, contact2: contact2) else {
            return 0.0
        }
        return result.overallScore
    }

    private func normalizePhone(_ phone: String) -> String {
        return phone.filter { $0.isNumber }
    }
}

// MARK: - Field Similarity Calculations
extension DuplicateDetector {
    func calculateNameSimilarity(contact1: ContactData, contact2: ContactData) -> Double {
        let firstName1 = contact1.firstName.trimmingCharacters(in: .whitespaces)
        let lastName1 = contact1.lastName.trimmingCharacters(in: .whitespaces)
        let firstName2 = contact2.firstName.trimmingCharacters(in: .whitespaces)
        let lastName2 = contact2.lastName.trimmingCharacters(in: .whitespaces)

        if firstName1.isEmpty && lastName1.isEmpty && firstName2.isEmpty && lastName2.isEmpty {
            return 0.0
        }

        let fullName1 = "\(firstName1) \(lastName1)".trimmingCharacters(in: .whitespaces)
        let fullName2 = "\(firstName2) \(lastName2)".trimmingCharacters(in: .whitespaces)

        let directScore = similarityEngine.nameSimilarity(
            firstName1: firstName1, lastName1: lastName1,
            firstName2: firstName2, lastName2: lastName2
        )

        let fullNameScore = similarityEngine.jaroWinklerSimilarity(fullName1, fullName2)
        return max(directScore, fullNameScore)
    }

    func calculateEmailSimilarity(contact1: ContactData, contact2: ContactData) -> Double {
        if contact1.emails.isEmpty || contact2.emails.isEmpty { return 0.0 }

        let emails1Set = Set(contact1.emails.map { $0.lowercased() })
        let emails2Set = Set(contact2.emails.map { $0.lowercased() })

        if !emails1Set.isDisjoint(with: emails2Set) { return 1.0 }

        var maxSim = 0.0
        for email1 in contact1.emails {
            for email2 in contact2.emails {
                maxSim = max(maxSim, similarityEngine.emailSimilarity(email1, email2))
            }
        }
        return maxSim
    }

    func calculatePhoneSimilarity(contact1: ContactData, contact2: ContactData) -> Double {
        if contact1.phoneNumbers.isEmpty || contact2.phoneNumbers.isEmpty { return 0.0 }

        let phones1 = contact1.phoneNumbers.map { normalizePhone($0) }
        let phones2 = contact2.phoneNumbers.map { normalizePhone($0) }

        if !Set(phones1).isDisjoint(with: Set(phones2)) { return 1.0 }

        for p1 in phones1 {
            for p2 in phones2 {
                if p1.count >= 7 && p2.count >= 7 {
                    if String(p1.suffix(7)) == String(p2.suffix(7)) { return 0.95 }
                }
            }
        }

        var maxSim = 0.0
        for phone1 in contact1.phoneNumbers {
            for phone2 in contact2.phoneNumbers {
                maxSim = max(maxSim, similarityEngine.phoneSimilarity(phone1, phone2))
            }
        }
        return maxSim
    }

    func calculateCompanySimilarity(contact1: ContactData, contact2: ContactData) -> Double {
        let company1 = contact1.company.trimmingCharacters(in: .whitespaces)
        let company2 = contact2.company.trimmingCharacters(in: .whitespaces)

        if company1.isEmpty || company2.isEmpty { return 0.0 }
        if company1.lowercased() == company2.lowercased() { return 1.0 }

        let stringSim = similarityEngine.jaroWinklerSimilarity(company1, company2)
        let semanticSim = similarityEngine.semanticSimilarity(company1, company2)
        return max(stringSim, semanticSim)
    }
}

// MARK: - Confidence Assessment
extension DuplicateDetector {
    func assessConfidence(score: Double) -> DuplicateConfidence {
        switch score {
        case 0.95...1.0: return .veryHigh
        case 0.85..<0.95: return .high
        case 0.75..<0.85: return .medium
        case 0.65..<0.75: return .low
        default: return .veryLow
        }
    }

    enum DuplicateConfidence: String {
        case veryHigh = "Very High"
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        case veryLow = "Very Low"

        var color: String {
            switch self {
            case .veryHigh: return "green"
            case .high: return "blue"
            case .medium: return "yellow"
            case .low: return "orange"
            case .veryLow: return "red"
            }
        }
    }
}
