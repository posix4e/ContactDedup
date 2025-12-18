//
//  ContactDedupUITests.swift
//  ContactDedupUITests
//
//  Created by alex newman on 12/18/25.
//

import XCTest

final class ContactDedupUITests: XCTestCase {

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
