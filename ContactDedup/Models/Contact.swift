import Foundation
import Contacts

// MARK: - Supporting Types for Contact Data

struct SocialProfile: Hashable, Codable {
    var service: String  // e.g., "twitter", "linkedin", "facebook"
    var username: String
    var urlString: String?

    var displayName: String {
        if !username.isEmpty {
            return "\(service): @\(username)"
        }
        return service
    }
}

struct InstantMessageAddress: Hashable, Codable {
    var service: String  // e.g., "Skype", "Slack", "Discord"
    var username: String
}

struct Relationship: Hashable, Codable {
    var name: String
    var label: String  // e.g., "spouse", "assistant", "manager"
}

struct LabeledDate: Hashable, Codable {
    var label: String  // e.g., "anniversary", "other"
    var date: DateComponents
}

struct ContactData: Identifiable, Hashable {
    let id: UUID
    var firstName: String
    var lastName: String
    var middleName: String
    var nickname: String
    var company: String
    var jobTitle: String
    var department: String
    var emails: [String]
    var phoneNumbers: [String]
    var addresses: [String]
    var urls: [String]
    var socialProfiles: [SocialProfile]
    var instantMessageAddresses: [InstantMessageAddress]
    var relationships: [Relationship]
    var birthday: DateComponents?
    var dates: [LabeledDate]
    var notes: String
    var imageData: Data?
    var source: ContactSource
    var appleIdentifier: String?
    var googleIdentifier: String?
    var linkedinIdentifier: String?
    var createdAt: Date
    var updatedAt: Date

    var fullName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? company : name
    }

    var displayName: String {
        if !fullName.isEmpty {
            return fullName
        }
        if let email = emails.first {
            return email
        }
        if let phone = phoneNumbers.first {
            return phone
        }
        return "No Name"
    }

    var hasContactInfo: Bool {
        return !emails.isEmpty || !phoneNumbers.isEmpty
    }

    var hasName: Bool {
        return !firstName.isEmpty || !lastName.isEmpty || !company.isEmpty
    }

    var isIncomplete: Bool {
        return hasName && !hasContactInfo
    }

    init(
        id: UUID = UUID(),
        firstName: String = "",
        lastName: String = "",
        middleName: String = "",
        nickname: String = "",
        company: String = "",
        jobTitle: String = "",
        department: String = "",
        emails: [String] = [],
        phoneNumbers: [String] = [],
        addresses: [String] = [],
        urls: [String] = [],
        socialProfiles: [SocialProfile] = [],
        instantMessageAddresses: [InstantMessageAddress] = [],
        relationships: [Relationship] = [],
        birthday: DateComponents? = nil,
        dates: [LabeledDate] = [],
        notes: String = "",
        imageData: Data? = nil,
        source: ContactSource = .apple,
        appleIdentifier: String? = nil,
        googleIdentifier: String? = nil,
        linkedinIdentifier: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.middleName = middleName
        self.nickname = nickname
        self.company = company
        self.jobTitle = jobTitle
        self.department = department
        self.emails = emails
        self.phoneNumbers = phoneNumbers
        self.addresses = addresses
        self.urls = urls
        self.socialProfiles = socialProfiles
        self.instantMessageAddresses = instantMessageAddresses
        self.relationships = relationships
        self.birthday = birthday
        self.dates = dates
        self.notes = notes
        self.imageData = imageData
        self.source = source
        self.appleIdentifier = appleIdentifier
        self.googleIdentifier = googleIdentifier
        self.linkedinIdentifier = linkedinIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ContactSource: String, Codable {
    case apple
    case google
    case linkedin
    case manual
}

enum DuplicateMatchType: String {
    case exactEmail = "Same Email"
    case exactPhone = "Same Phone"
    case similar = "Similar"

    var icon: String {
        switch self {
        case .exactEmail: return "envelope.fill"
        case .exactPhone: return "phone.fill"
        case .similar: return "person.2.fill"
        }
    }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    var contacts: [ContactData]
    var matchType: DuplicateMatchType
    var nameSimilarity: Double
    var additionalScores: [String: Double]  // e.g., ["company": 0.8]

    var primaryContact: ContactData? {
        contacts.first
    }

    var matchDescription: String {
        matchType.rawValue
    }

    // For backwards compatibility
    var similarityScore: Double {
        switch matchType {
        case .exactEmail, .exactPhone:
            return 1.0
        case .similar:
            return nameSimilarity
        }
    }
}
