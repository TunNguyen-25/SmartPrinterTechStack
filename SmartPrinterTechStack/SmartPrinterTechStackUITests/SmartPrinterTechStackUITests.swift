import XCTest

final class SmartPrinterTechStackUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testThreeTabsAndSamplePersistsAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons.matching(identifier: "File").firstMatch.waitForExistence(timeout: 10))
        if app.tabBars.firstMatch.exists { XCTAssertEqual(app.tabBars.buttons.count, 3) }
        XCTAssertTrue(app.buttons.matching(identifier: "Printer").firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(identifier: "Scan").firstMatch.exists)
        app.buttons.matching(identifier: "File").firstMatch.tap()
        app.buttons["importDocuments"].tap()
        app.buttons["samplePDF"].tap()
        XCTAssertTrue(app.buttons["finishImport"].waitForExistence(timeout: 10))
        app.buttons["finishImport"].tap()
        let row = app.cells.containing(.staticText, identifier: "Sample.pdf").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["Sample.pdf"].waitForExistence(timeout: 5))
        app.buttons["documentActions"].tap()
        app.buttons["Đổi tên"].tap()
        let name = "Review-\(UUID().uuidString).pdf"
        let field = app.alerts.textFields.firstMatch
        let existing = field.value as? String ?? ""
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + name)
        app.alerts.buttons["Lưu"].tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.buttons.matching(identifier: "File").firstMatch.tap()
        let persisted = app.cells.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: 10))
        persisted.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
        app.buttons["documentActions"].tap()
        app.buttons["Xóa"].tap()
        app.alerts.buttons["Xóa"].tap()
        XCTAssertTrue(app.navigationBars["File"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCancelFilesPickerKeepsLibraryUsable() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons.matching(identifier: "File").firstMatch.tap()
        app.buttons["importDocuments"].tap()
        app.buttons["importFiles"].tap()
        let cancel = app.descendants(matching: .any).matching(identifier: "Cancel").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(app.buttons["importDocuments"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCancelPhotosPickerKeepsLibraryUsable() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons.matching(identifier: "File").firstMatch.tap()
        app.buttons["importDocuments"].tap()
        app.buttons["importPhotos"].tap()
        let cancel = app.descendants(matching: .any).matching(identifier: "Cancel").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(app.buttons["importDocuments"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testImagePreviewAndExportCancel() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons.matching(identifier: "File").firstMatch.tap()
        app.buttons["importDocuments"].tap()
        app.buttons["sampleImage"].tap()
        XCTAssertTrue(app.buttons["finishImport"].waitForExistence(timeout: 10))
        app.buttons["finishImport"].tap()
        let row = app.cells.containing(.staticText, identifier: "Sample.png").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.images["Sample.png"].waitForExistence(timeout: 10))
        app.buttons["documentActions"].tap()
        app.buttons["Xuất sang Files"].tap()
        let cancel = app.descendants(matching: .any).matching(identifier: "Cancel").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        if cancel.isHittable {
            cancel.tap()
        } else {
            app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].swipeDown()
        }
        let actions = app.buttons["documentActions"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: actions)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        XCTAssertTrue(app.images["Sample.png"].exists)
        actions.tap()
        app.buttons["Xóa"].tap()
        app.alerts.buttons["Xóa"].tap()
        XCTAssertTrue(app.navigationBars["File"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testShareSheetOpensFromDocumentActions() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons.matching(identifier: "File").firstMatch.tap()
        app.buttons["importDocuments"].tap()
        app.buttons["sampleText"].tap()
        XCTAssertTrue(app.buttons["finishImport"].waitForExistence(timeout: 10))
        app.buttons["finishImport"].tap()
        let row = app.cells.containing(.staticText, identifier: "Sample.txt").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["Sample.txt"].waitForExistence(timeout: 5))
        app.buttons["documentActions"].tap()
        app.buttons["Chia sẻ"].tap()
        let copy = app.descendants(matching: .any).matching(identifier: "Copy").firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        copy.tap()
        XCTAssertTrue(app.buttons["documentActions"].waitForExistence(timeout: 5))
        app.buttons["documentActions"].tap()
        app.buttons["Xóa"].tap()
        app.alerts.buttons["Xóa"].tap()
        XCTAssertTrue(app.navigationBars["File"].waitForExistence(timeout: 5))
    }
}
