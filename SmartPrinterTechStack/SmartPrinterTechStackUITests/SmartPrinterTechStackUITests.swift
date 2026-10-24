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
    func testImageShareCanSaveToPhotos() throws {
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
        app.buttons["Chia sẻ"].tap()
        let save = app.descendants(matching: .any).matching(identifier: "Save Image").firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 3) {
            let allow = permission.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Allow'")).firstMatch
            XCTAssertTrue(allow.exists, permission.debugDescription)
            allow.tap()
        }
        let actions = app.buttons["documentActions"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: actions)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
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
    @MainActor
    func testPrinterPickerCanCancel() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons.matching(identifier: "Printer").firstMatch.tap()
        let choose = app.cells["choosePrinter"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        let cancel = app.descendants(matching: .any).matching(identifier: "Cancel").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Đã hủy chọn' ")).firstMatch.exists)
    }

    @MainActor
    func testCalibrationReviewPrintSheetAndCancel() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons.matching(identifier: "Printer").firstMatch.tap()
        let calibration = app.cells["calibrationA4"]
        XCTAssertTrue(calibration.waitForExistence(timeout: 5))
        calibration.tap()
        XCTAssertTrue(app.navigationBars["Calibration-A4.pdf"].waitForExistence(timeout: 10))
        app.buttons["documentActions"].tap()
        app.buttons["printDocument"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Close' OR label == 'Cancel'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        if app.alerts["Kết quả yêu cầu in"].waitForExistence(timeout: 3) {
            app.alerts.buttons["Đóng"].tap()
        }
        XCTAssertTrue(app.buttons["documentActions"].waitForExistence(timeout: 5))
        app.buttons["documentActions"].tap()
        app.buttons["directPrint"].tap()
        XCTAssertTrue(app.alerts["Không thể hoàn tất"].waitForExistence(timeout: 10))
        app.alerts.buttons["Đóng"].tap()
        app.buttons["documentActions"].tap()
        app.buttons["Xóa"].tap()
        app.alerts.buttons["Xóa"].tap()
        XCTAssertTrue(app.navigationBars["Printer"].waitForExistence(timeout: 5))
    }

}
