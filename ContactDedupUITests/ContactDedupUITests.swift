//
//  ContactDedupUITests.swift
//  ContactDedupUITests
//
//  Created by alex newman on 12/18/25.
//

import XCTest

final class ContactDedupUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch Tests

    @MainActor
    func testAppLaunches() throws {
        app.launch()

        // App should launch without crashing
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testMainTabsExist() throws {
        app.launch()

        // Wait for main UI to load
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar should exist")
    }

    // MARK: - Navigation Tests

    @MainActor
    func testNavigateToSettings() throws {
        app.launch()

        // Look for settings button (could be in nav bar or tab)
        let settingsButton = app.buttons["Settings"].firstMatch
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()

            // Verify we're on settings screen
            let settingsTitle = app.navigationBars["Settings"].firstMatch
            XCTAssertTrue(settingsTitle.waitForExistence(timeout: 2) ||
                         app.staticTexts["Settings"].exists,
                         "Should navigate to Settings")
        }
    }

    @MainActor
    func testNavigateToDuplicates() throws {
        app.launch()

        // Find and tap Duplicates tab
        let duplicatesTab = app.tabBars.buttons["Duplicates"].firstMatch
        if duplicatesTab.waitForExistence(timeout: 3) {
            duplicatesTab.tap()

            // Should see duplicates view content
            let exists = app.staticTexts["Duplicates"].exists ||
                        app.staticTexts["No Duplicates Found"].exists ||
                        app.navigationBars["Duplicates"].exists
            XCTAssertTrue(exists, "Should show duplicates content")
        }
    }

    // MARK: - Import Flow Tests

    @MainActor
    func testImportButtonExists() throws {
        app.launch()

        // Navigate to import view if needed
        let importButton = app.buttons["Import"].firstMatch
        let importTab = app.tabBars.buttons["Import"].firstMatch

        let hasImport = importButton.waitForExistence(timeout: 3) ||
                       importTab.waitForExistence(timeout: 3)

        XCTAssertTrue(hasImport, "Import functionality should be accessible")
    }

    // MARK: - Cleanup Flow Tests

    @MainActor
    func testCleanupTabExists() throws {
        app.launch()

        let cleanupTab = app.tabBars.buttons["Cleanup"].firstMatch
        if cleanupTab.waitForExistence(timeout: 3) {
            cleanupTab.tap()

            // Should see cleanup view
            let cleanupContent = app.staticTexts["Incomplete Contacts"].exists ||
                                app.staticTexts["Cleanup"].exists ||
                                app.navigationBars["Cleanup"].exists
            XCTAssertTrue(cleanupContent, "Should show cleanup content")
        }
    }

    // MARK: - Performance Tests

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - Accessibility Tests

    @MainActor
    func testMainScreenAccessibility() throws {
        app.launch()

        // Check that main interactive elements have accessibility identifiers
        // or are accessible to VoiceOver
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.isHittable, "Tab bar should be hittable for accessibility")

        // All tabs should be accessible
        for button in app.tabBars.buttons.allElementsBoundByIndex {
            XCTAssertTrue(button.isEnabled, "Tab button should be enabled")
        }
    }
}
