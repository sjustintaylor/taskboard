import XCTest

/// Optional native UI regression checks. Core persistence tests run in taskboardTests.
final class TaskboardUITests: XCTestCase {
    @MainActor
    func testWelcomeAndRichInspector() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        let welcome = app.windows["Welcome to Taskboard"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))
        XCTAssertFalse(app.dialogs.firstMatch.exists)
        welcome.buttons["New Board"].click()
        let newTask = app.buttons["New Task"]
        XCTAssertTrue(newTask.waitForExistence(timeout: 5))
        XCTAssertFalse(welcome.exists)
        newTask.click()
        let description = app.textViews["Description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.click()
        description.typeText("Formatted description")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("b", modifierFlags: .command)
        app.buttons["Add Criterion"].click()
        let criterion = app.textViews["Criterion 1"]
        XCTAssertTrue(criterion.waitForExistence(timeout: 5))
        criterion.click()
        criterion.typeText("First line\nSecond line")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No dependencies")).firstMatch.exists)
        app.buttons["Manage Dependencies…"].click()
        XCTAssertTrue(app.textFields["Search title or ID"].waitForExistence(timeout: 5))
        app.buttons["Done"].click()
    }

    @MainActor
    func testNewTaskAndInspector() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].click() }
        app.typeKey("n", modifierFlags: .command)
        let newTask = app.buttons["New Task"]
        XCTAssertTrue(newTask.waitForExistence(timeout: 5))
        newTask.click()
        let title = app.textFields["taskTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "New task")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(title.exists)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No Todo tasks"].exists)
    }
}
