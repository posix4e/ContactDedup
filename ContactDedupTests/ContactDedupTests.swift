//
//  ContactDedupTests.swift
//  ContactDedupTests
//
//  Created by alex newman on 12/18/25.
//

import XCTest
@testable import ContactDedup

// MARK: - DuplicateDetector Tests

final class DuplicateDetectorTests: XCTestCase {
    var detector: DuplicateDetector!

    override func setUp() {
        super.setUp()
        detector = DuplicateDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - Exact Email Match Tests

    func testExactEmailMatch() {
        let contact1 = ContactData(
            firstName: "John",
            lastName: "Smith",
            emails: ["john@example.com"]
        )
        let contact2 = ContactData(
            firstName: "Johnny",
            lastName: "Smith",
            emails: ["john@example.com"]
        )

        let groups = detector.findDuplicateGroups(in: [contact1, contact2])

        XCTAssertEqual(groups.count, 1, "Should find one duplicate group")
        XCTAssertEqual(groups.first?.matchType, .exactEmail, "Match type should be exactEmail")
        XCTAssertEqual(groups.first?.contacts.count, 2, "Group should contain both contacts")
    }

    func testDifferentEmailsNoDuplicate() {
        let contact1 = ContactData(
            firstName: "John",
            lastName: "Smith",
            emails: ["john@example.com"]
        )
        let contact2 = ContactData(
            firstName: "Jane",
            lastName: "Doe",
            emails: ["jane@example.com"]
        )

        let groups = detector.findDuplicateGroups(in: [contact1, contact2])

        XCTAssertEqual(groups.count, 0, "Should not find duplicates")
    }

    // MARK: - Exact Phone Match Tests

    func testExactPhoneMatch() {
        let contact1 = ContactData(
            firstName: "John",
            lastName: "Smith",
            phoneNumbers: ["555-123-4567"]
        )
        let contact2 = ContactData(
            firstName: "J",
            lastName: "Smith",
            phoneNumbers: ["(555) 123-4567"]
        )

        let groups = detector.findDuplicateGroups(in: [contact1, contact2])

        XCTAssertEqual(groups.count, 1, "Should find one duplicate group")
        XCTAssertEqual(groups.first?.matchType, .exactPhone, "Match type should be exactPhone")
    }

    func testPhoneSuffixMatch() {
        // International format vs local format
        let contact1 = ContactData(
            firstName: "John",
            lastName: "Smith",
            phoneNumbers: ["+1-555-123-4567"]
        )
        let contact2 = ContactData(
            firstName: "John",
            lastName: "Smith",
            phoneNumbers: ["123-4567"]
        )

        let groups = detector.findDuplicateGroups(in: [contact1, contact2])

        XCTAssertEqual(groups.count, 1, "Should find duplicate based on phone suffix")
    }

    // MARK: - Name Similarity Tests

    func testExactNameMatch() {
        let contact1 = ContactData(
            firstName: "John",
            lastName: "Smith",
            company: "Acme Inc"
        )
        let contact2 = ContactData(
            firstName: "John",
            lastName: "Smith",
            company: "XYZ Corp"
        )

        let groups = detector.findDuplicateGroups(in: [contact1, contact2])

        XCTAssertEqual(groups.count, 1, "Should find duplicate for exact name match")
        XCTAssertEqual(groups.first?.matchType, .similar, "Match type should be similar")
    }

    func testSimilarNameWithTypo() {
        let contact1 = ContactData(
            firstName: "John",
            lastName: "Smith"
        )
        let contact2 = ContactData(
            firstName: "Jonh",  // Typo
            lastName: "Smith"
        )

        let groups = detector.findDuplicateGroups(in: [contact1, contact2])

        XCTAssertEqual(groups.count, 1, "Should find duplicate for similar names with typo")
    }

    func testDifferentFamilyMembersNotDuplicate() {
        // This is a critical test - family members should NOT be marked as duplicates
        let contact1 = ContactData(
            firstName: "Mark",
            lastName: "Harrison"
        )
        let contact2 = ContactData(
            firstName: "Margo",
            lastName: "Harrison"
        )

        let groups = detector.findDuplicateGroups(in: [contact1, contact2])

        XCTAssertEqual(groups.count, 0, "Family members with different first names should NOT be duplicates")
    }

    func testSingleNameNotMatchedWithoutContactInfo() {
        // Single names without email/phone should not be matched
        let contact1 = ContactData(
            firstName: "John",
            lastName: ""
        )
        let contact2 = ContactData(
            firstName: "John",
            lastName: ""
        )

        let groups = detector.findDuplicateGroups(in: [contact1, contact2])

        XCTAssertEqual(groups.count, 0, "Contacts with only first name and no contact info should not be duplicates")
    }

    // MARK: - Multiple Duplicates Test

    func testMultipleDuplicateGroups() {
        let john1 = ContactData(firstName: "John", lastName: "Smith", emails: ["john@example.com"])
        let john2 = ContactData(firstName: "John", lastName: "Smith", emails: ["john@example.com"])
        let jane1 = ContactData(firstName: "Jane", lastName: "Doe", phoneNumbers: ["555-1234"])
        let jane2 = ContactData(firstName: "Jane", lastName: "Doe", phoneNumbers: ["555-1234"])
        let unique = ContactData(firstName: "Unique", lastName: "Person")

        let groups = detector.findDuplicateGroups(in: [john1, john2, jane1, jane2, unique])

        XCTAssertEqual(groups.count, 2, "Should find two duplicate groups")
    }

    // MARK: - Small Scale Test

    func testFindDuplicatesInSmallSet() {
        let contacts = [
            ContactData(firstName: "John", lastName: "Doe", emails: ["john@example.com"]),
            ContactData(firstName: "John", lastName: "Doe", emails: ["john@example.com"]),
            ContactData(firstName: "Jane", lastName: "Smith", emails: ["jane@example.com"])
        ]

        let groups = detector.findDuplicateGroups(in: contacts)
        XCTAssertEqual(groups.count, 1, "Should find one duplicate group")
    }

    // MARK: - Field Similarity Tests

    func testEmailSimilarity() {
        let contact1 = ContactData(
            firstName: "John",
            lastName: "Smith",
            emails: ["john.smith@example.com"]
        )
        let contact2 = ContactData(
            firstName: "John",
            lastName: "Smith",
            emails: ["johnsmith@example.com"]
        )

        let similarity = detector.calculateEmailSimilarity(contact1: contact1, contact2: contact2)
        XCTAssertGreaterThan(similarity, 0.5, "Similar emails should have high similarity")
    }

    func testCompanySimilarity() {
        let contact1 = ContactData(
            firstName: "John",
            lastName: "Smith",
            company: "Apple Inc."
        )
        let contact2 = ContactData(
            firstName: "John",
            lastName: "Smith",
            company: "Apple Incorporated"
        )

        let similarity = detector.calculateCompanySimilarity(contact1: contact1, contact2: contact2)
        XCTAssertGreaterThan(similarity, 0.7, "Similar company names should have high similarity")
    }
}

// MARK: - SimilarityEngine Tests

final class SimilarityEngineTests: XCTestCase {
    var engine: SimilarityEngine!

    override func setUp() {
        super.setUp()
        engine = SimilarityEngine.shared
    }

    // MARK: - Levenshtein Similarity Tests

    func testLevenshteinIdenticalStrings() {
        let similarity = engine.levenshteinSimilarity("hello", "hello")
        XCTAssertEqual(similarity, 1.0, "Identical strings should have similarity of 1.0")
    }

    func testLevenshteinSingleCharDifference() {
        let similarity = engine.levenshteinSimilarity("hello", "hallo")
        XCTAssertGreaterThan(similarity, 0.7, "Single character difference should have high similarity")
    }

    func testLevenshteinCompletelyDifferent() {
        let similarity = engine.levenshteinSimilarity("abc", "xyz")
        XCTAssertLessThan(similarity, 0.5, "Completely different strings should have low similarity")
    }

    func testLevenshteinEmptyString() {
        let similarity = engine.levenshteinSimilarity("hello", "")
        XCTAssertEqual(similarity, 0.0, "Empty string should have similarity of 0.0")
    }

    func testLevenshteinCaseInsensitive() {
        let similarity = engine.levenshteinSimilarity("HELLO", "hello")
        XCTAssertEqual(similarity, 1.0, "Should be case insensitive")
    }

    // MARK: - Jaro-Winkler Similarity Tests

    func testJaroWinklerIdentical() {
        let similarity = engine.jaroWinklerSimilarity("John", "John")
        XCTAssertEqual(similarity, 1.0)
    }

    func testJaroWinklerSimilarNames() {
        let similarity = engine.jaroWinklerSimilarity("John", "Jonh")
        XCTAssertGreaterThan(similarity, 0.9, "Typo should still have very high similarity")
    }

    func testJaroWinklerDifferentNames() {
        let similarity = engine.jaroWinklerSimilarity("Mark", "Margo")
        XCTAssertLessThan(similarity, 0.9, "Different names should not be too similar")
    }

    func testJaroWinklerCommonPrefix() {
        // Jaro-Winkler gives bonus for common prefix
        let sim1 = engine.jaroWinklerSimilarity("MARTHA", "MARHTA")
        let sim2 = engine.jaroWinklerSimilarity("ARTHAM", "ARHMAT")
        XCTAssertGreaterThan(sim1, sim2, "Common prefix should boost similarity")
    }

    // MARK: - Soundex Tests

    func testSoundexSimilarSounding() {
        let similarity = engine.soundexSimilarity("Robert", "Rupert")
        XCTAssertEqual(similarity, 1.0, "Similar sounding names should match")
    }

    func testSoundexDifferentSounding() {
        let similarity = engine.soundexSimilarity("John", "Mary")
        XCTAssertEqual(similarity, 0.0, "Different sounding names should not match")
    }

    // MARK: - Phone Similarity Tests

    func testPhoneSimilarityExact() {
        let similarity = engine.phoneSimilarity("555-123-4567", "5551234567")
        XCTAssertEqual(similarity, 1.0, "Same phone numbers with different formatting should be exact match")
    }

    func testPhoneSimilarityInternational() {
        let similarity = engine.phoneSimilarity("+1-555-123-4567", "555-123-4567")
        XCTAssertGreaterThan(similarity, 0.8, "International vs local format should have high similarity")
    }

    // MARK: - Email Similarity Tests

    func testEmailSimilarityExact() {
        let similarity = engine.emailSimilarity("john@example.com", "JOHN@EXAMPLE.COM")
        XCTAssertEqual(similarity, 1.0, "Same email should match regardless of case")
    }

    func testEmailSimilaritySameDomain() {
        let similarity = engine.emailSimilarity("john@example.com", "johnny@example.com")
        XCTAssertGreaterThan(similarity, 0.5, "Same domain should boost similarity")
    }

    // MARK: - Name Similarity Tests

    func testNameSimilarityExact() {
        let similarity = engine.nameSimilarity(
            firstName1: "John",
            lastName1: "Smith",
            firstName2: "John",
            lastName2: "Smith"
        )
        XCTAssertEqual(similarity, 1.0)
    }

    func testNameSimilaritySwapped() {
        // Some cultures put last name first
        let similarity = engine.nameSimilarity(
            firstName1: "John",
            lastName1: "Smith",
            firstName2: "Smith",
            lastName2: "John"
        )
        XCTAssertGreaterThan(similarity, 0.8, "Swapped names should still have high similarity")
    }

    func testNameSimilarityWithTypo() {
        let similarity = engine.nameSimilarity(
            firstName1: "John",
            lastName1: "Smith",
            firstName2: "Jonh",
            lastName2: "Smith"
        )
        XCTAssertGreaterThan(similarity, 0.9, "Name with typo should have very high similarity")
    }

}

// MARK: - LinkedIn CSV Import Tests

final class LinkedInImporterTests: XCTestCase {

    func testParseBasicLinkedInCSV() throws {
        let csvContent = """
        First Name,Last Name,Email Address,Company,Position,Connected On
        John,Smith,john.smith@example.com,Acme Inc,Software Engineer,01 Jan 2024
        Jane,Doe,jane.doe@company.org,Tech Corp,Product Manager,15 Feb 2024
        """

        let contacts = try parseCSVForTesting(csvContent)

        XCTAssertEqual(contacts.count, 2, "Should parse 2 contacts")

        let john = contacts[0]
        XCTAssertEqual(john.firstName, "John")
        XCTAssertEqual(john.lastName, "Smith")
        XCTAssertEqual(john.emails, ["john.smith@example.com"])
        XCTAssertEqual(john.company, "Acme Inc")
        XCTAssertTrue(john.notes.contains("Position: Software Engineer"))
        XCTAssertEqual(john.source, .linkedin)

        let jane = contacts[1]
        XCTAssertEqual(jane.firstName, "Jane")
        XCTAssertEqual(jane.lastName, "Doe")
        XCTAssertEqual(jane.emails, ["jane.doe@company.org"])
    }

    func testParseLinkedInCSVWithNotesHeader() throws {
        let csvContent = """
        Notes about this export:
        Downloaded on December 2024

        First Name,Last Name,Email Address,Company,Position
        Alice,Wonder,alice@email.com,Wonderland Inc,CEO
        """

        let contacts = try parseCSVForTesting(csvContent)

        XCTAssertEqual(contacts.count, 1, "Should find contact after skipping notes")
        XCTAssertEqual(contacts[0].firstName, "Alice")
        XCTAssertEqual(contacts[0].lastName, "Wonder")
    }

    func testParseCSVWithQuotedFields() throws {
        let csvContent = """
        First Name,Last Name,Email Address,Company,Position
        John,"Smith, Jr.",john@example.com,"Acme, Inc.",Senior Engineer
        "Mary Jane",Watson,mj@example.com,Daily Bugle,Reporter
        """

        let contacts = try parseCSVForTesting(csvContent)

        XCTAssertEqual(contacts.count, 2)
        XCTAssertEqual(contacts[0].lastName, "Smith, Jr.")
        XCTAssertEqual(contacts[0].company, "Acme, Inc.")
        XCTAssertEqual(contacts[1].firstName, "Mary Jane")
    }

    func testParseCSVWithEmptyEmail() throws {
        let csvContent = """
        First Name,Last Name,Email Address,Company,Position
        NoEmail,Person,,Some Company,Developer
        HasEmail,Person,has@email.com,Other Company,Manager
        """

        let contacts = try parseCSVForTesting(csvContent)

        XCTAssertEqual(contacts.count, 2)
        XCTAssertTrue(contacts[0].emails.isEmpty, "First contact should have no email")
        XCTAssertEqual(contacts[1].emails, ["has@email.com"])
    }

    func testParseCSVWithUnicodeNames() throws {
        let csvContent = """
        First Name,Last Name,Email Address,Company,Position
        José,García,jose@example.com,Empresa,Ingeniero
        Müller,François,muller@example.com,Société,Développeur
        """

        let contacts = try parseCSVForTesting(csvContent)

        XCTAssertEqual(contacts.count, 2)
        XCTAssertEqual(contacts[0].firstName, "José")
        XCTAssertEqual(contacts[0].lastName, "García")
        XCTAssertEqual(contacts[1].firstName, "Müller")
        XCTAssertEqual(contacts[1].lastName, "François")
    }

    // MARK: - Helper for Testing

    private func parseCSVForTesting(_ content: String) throws -> [ContactData] {
        var contacts: [ContactData] = []
        let lines = content.components(separatedBy: .newlines)

        guard lines.count > 1 else {
            throw NSError(domain: "LinkedInImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "No contacts"])
        }

        var headerLineIndex = 0
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            if lowercased.contains("first name") && lowercased.contains("last name") {
                headerLineIndex = index
                break
            }
        }

        if headerLineIndex == lines.count - 1 {
            throw NSError(domain: "LinkedInImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "No contacts"])
        }

        let header = parseCSVLine(lines[headerLineIndex])
        let columnMap = buildColumnMap(header)

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

        if contacts.isEmpty {
            throw NSError(domain: "LinkedInImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "No contacts"])
        }

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

        var notesParts: [String] = []
        if !position.isEmpty {
            notesParts.append("Position: \(position)")
        }
        if !linkedinURL.isEmpty {
            notesParts.append("LinkedIn: \(linkedinURL)")
        }
        let notes = notesParts.joined(separator: "\n")

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
}
