import Foundation
import UniformTypeIdentifiers

@MainActor
class LinkedInImporter {
    private let appleManager = AppleContactsManager.shared

    struct ImportResult {
        var imported: Int = 0
        var merged: Int = 0
        var skipped: Int = 0
        var errors: [String] = []
    }

    enum ImportError: Error, LocalizedError {
        case invalidFile
        case parseError(String)
        case noContacts

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "The selected file is not a valid LinkedIn export."
            case .parseError(let message):
                return "Failed to parse CSV: \(message)"
            case .noContacts:
                return "No contacts found in the file."
            }
        }
    }

    // LinkedIn CSV columns (from "Connections" export)
    // First Name, Last Name, Email Address, Company, Position, Connected On

    func importFromCSV(
        url: URL,
        existingContacts: [ContactData],
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> ImportResult {
        // Get file access
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.invalidFile
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFile
        }

        let linkedInContacts = try parseCSV(content)

        if linkedInContacts.isEmpty {
            throw ImportError.noContacts
        }

        return try await importContacts(linkedInContacts, existingContacts: existingContacts, progressHandler: progressHandler)
    }

    private func parseCSV(_ content: String) throws -> [ContactData] {
        var contacts: [ContactData] = []
        let lines = content.components(separatedBy: .newlines)

        guard lines.count > 1 else {
            throw ImportError.noContacts
        }

        // Find the header line - LinkedIn exports have notes at the top
        // Look for a line that contains "First Name" to find the actual header
        var headerLineIndex = 0
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            if lowercased.contains("first name") && lowercased.contains("last name") {
                headerLineIndex = index
                break
            }
        }

        // Parse header to find column indices
        let header = parseCSVLine(lines[headerLineIndex])
        let columnMap = buildColumnMap(header)

        print("[LinkedIn] Found header at line \(headerLineIndex): \(header)")
        print("[LinkedIn] Column map: \(columnMap)")

        // Skip header row, parse data rows
        for i in (headerLineIndex + 1)..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let fields = parseCSVLine(line)
            if fields.isEmpty { continue }

            let contact = buildContact(from: fields, columnMap: columnMap)
            if !contact.firstName.isEmpty || !contact.lastName.isEmpty {
                contacts.append(contact)
            }
        }

        print("[LinkedIn] Parsed \(contacts.count) contacts")
        return contacts
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))

        return fields
    }

    private func buildColumnMap(_ header: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (index, column) in header.enumerated() {
            let normalized = column.lowercased().trimmingCharacters(in: .whitespaces)
            map[normalized] = index
        }
        return map
    }

    private func buildContact(from fields: [String], columnMap: [String: Int]) -> ContactData {
        func getValue(_ keys: [String]) -> String {
            for key in keys {
                if let index = columnMap[key], index < fields.count {
                    return fields[index]
                }
            }
            return ""
        }

        let firstName = getValue(["first name", "firstname"])
        let lastName = getValue(["last name", "lastname"])
        let email = getValue(["email address", "email", "e-mail"])
        let company = getValue(["company", "organization"])
        let position = getValue(["position", "title", "job title"])
        let linkedinURL = getValue(["url", "linkedin url", "profile url"])

        let emails = email.isEmpty ? [] : [email]

        // Build notes with position and LinkedIn URL
        var notesParts: [String] = []
        if !position.isEmpty {
            notesParts.append("Position: \(position)")
        }
        if !linkedinURL.isEmpty {
            notesParts.append("LinkedIn: \(linkedinURL)")
        }
        let notes = notesParts.joined(separator: "\n")

        // Use LinkedIn URL as identifier if available, otherwise use name
        let identifier = linkedinURL.isEmpty ? "\(firstName.lowercased()).\(lastName.lowercased())" : linkedinURL

        return ContactData(
            firstName: firstName,
            lastName: lastName,
            company: company,
            emails: emails,
            phoneNumbers: [],
            addresses: [],
            notes: notes,
            imageData: nil,
            source: .linkedin,
            linkedinIdentifier: identifier
        )
    }

    private func importContacts(
        _ linkedInContacts: [ContactData],
        existingContacts: [ContactData],
        progressHandler: ((Int, Int) -> Void)?
    ) async throws -> ImportResult {
        var result = ImportResult()
        let total = linkedInContacts.count

        // Build indexes for matching
        let emailIndex = buildEmailIndex(existingContacts)
        let nameIndex = buildNameIndex(existingContacts)
        let contactsById = Dictionary(uniqueKeysWithValues: existingContacts.map { ($0.id, $0) })

        for (index, linkedInContact) in linkedInContacts.enumerated() {
            progressHandler?(index + 1, total)

            // Skip contacts with no email (most LinkedIn contacts won't have one)
            if linkedInContact.emails.isEmpty {
                result.skipped += 1
                continue
            }

            // Check for existing duplicate by email or name
            if let existingMatch = findExactMatch(for: linkedInContact, emailIndex: emailIndex, nameIndex: nameIndex, contactsById: contactsById) {
                // Merge into existing contact
                let merged = mergeContacts(existing: existingMatch, incoming: linkedInContact)
                do {
                    try appleManager.updateContact(merged)
                    result.merged += 1
                } catch {
                    result.errors.append("Failed to merge \(linkedInContact.displayName): \(error.localizedDescription)")
                }
            } else {
                // Import as new contact
                do {
                    try appleManager.createContact(linkedInContact)
                    result.imported += 1
                } catch {
                    result.errors.append("Failed to import \(linkedInContact.displayName): \(error.localizedDescription)")
                }
            }
        }

        return result
    }

    private func findExactMatch(
        for contact: ContactData,
        emailIndex: [String: UUID],
        nameIndex: [String: UUID],
        contactsById: [UUID: ContactData]
    ) -> ContactData? {
        // Check email first
        for email in contact.emails {
            let normalized = email.lowercased()
            if let matchId = emailIndex[normalized], let match = contactsById[matchId] {
                return match
            }
        }

        // Check exact name match
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

    private func mergeContacts(existing: ContactData, incoming: ContactData) -> ContactData {
        var merged = existing

        // Add unique emails
        let newEmails = incoming.emails.filter { email in
            !existing.emails.contains { $0.lowercased() == email.lowercased() }
        }
        merged.emails.append(contentsOf: newEmails)

        // Fill in missing fields
        if merged.firstName.isEmpty { merged.firstName = incoming.firstName }
        if merged.lastName.isEmpty { merged.lastName = incoming.lastName }
        if merged.company.isEmpty { merged.company = incoming.company }
        if merged.notes.isEmpty { merged.notes = incoming.notes }

        // Store LinkedIn identifier
        merged.linkedinIdentifier = incoming.linkedinIdentifier

        return merged
    }
}
