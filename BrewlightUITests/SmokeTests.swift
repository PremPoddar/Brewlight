import XCTest

/// Launch → search → open detail → settings → appearance, in demo mode (no real Homebrew).
final class SmokeTests: XCTestCase {
    @MainActor
    func testSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()

        let search = app.textFields["Search packages"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        // The list's type filter is restored from the last session; `type:` in the query overrides it.
        search.click()
        search.typeText("type:formula ripgrep")
        let row = app.descendants(matching: .any)["row-formula:ripgrep"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        let detail = app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'The Silver Searcher' OR label CONTAINS 'The Silver Searcher'")).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        app.buttons["Appearance"].firstMatch.click()
        app.radioButtons["Dark"].firstMatch.click()
        app.radioButtons["System"].firstMatch.click()
    }
}

final class ActivityDrawerTests: XCTestCase {
    @MainActor
    func testCloseButtonHidesDrawer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(app.textFields["Search packages"].waitForExistence(timeout: 20))

        app.typeKey("l", modifierFlags: .command)
        let close = app.buttons["Close activity"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "drawer did not open")
        close.click()
        XCTAssertTrue(close.waitForNonExistence(timeout: 3), "drawer did not close")

        // Reopen from the toolbar; Esc closes it too.
        app.buttons["Activity"].firstMatch.click()
        XCTAssertTrue(close.waitForExistence(timeout: 5), "toolbar button did not reopen the drawer")
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(close.waitForNonExistence(timeout: 3), "Esc did not close the drawer")
    }
}

final class PaletteTests: XCTestCase {
    @MainActor
    func testTabShowsActionsForSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(app.textFields["Search packages"].waitForExistence(timeout: 20))

        app.typeKey("k", modifierFlags: .command)
        let field = app.textFields["Command palette search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Type straight away, like a person would after ⌘K: the field must already have focus.
        app.typeText("ripgrep")
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        let header = app.staticTexts["Actions for ripgrep"]
        XCTAssertTrue(header.waitForExistence(timeout: 3), "Tab did not open the package's actions")
        XCTAssertTrue(app.staticTexts["Reinstall"].exists)

        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(header.waitForNonExistence(timeout: 3), "Esc did not go back to results")
    }
}
