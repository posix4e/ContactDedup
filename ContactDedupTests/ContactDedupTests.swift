//
//  ContactDedupTests.swift
//  ContactDedupTests
//
//  Created by alex newman on 12/18/25.
//

import XCTest
@testable import ContactDedup

final class ContactDedupTests: XCTestCase {

    func testBasicDuplicateDetection() {
        let detector = DuplicateDetector()
        let contact1 = ContactData(firstName: "John", lastName: "Doe", emails: ["john@example.com"])
        let contact2 = ContactData(firstName: "John", lastName: "Doe", emails: ["john@example.com"])

        let groups = detector.findDuplicateGroups(in: [contact1, contact2])
        XCTAssertEqual(groups.count, 1)
    }

    func testNoDuplicates() {
        let detector = DuplicateDetector()
        let contact1 = ContactData(firstName: "John", lastName: "Doe", emails: ["john@example.com"])
        let contact2 = ContactData(firstName: "Jane", lastName: "Smith", emails: ["jane@example.com"])

        let groups = detector.findDuplicateGroups(in: [contact1, contact2])
        XCTAssertEqual(groups.count, 0)
    }
}
