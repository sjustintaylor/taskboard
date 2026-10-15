import XCTest

/// Optional native UI regression checks. Core persistence tests run in taskboardTests.
final class TaskboardUITests: XCTestCase {
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
