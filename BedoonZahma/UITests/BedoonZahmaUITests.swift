import XCTest

/// اختبارات واجهة أساسية تعمل على المحاكي بوضع DevMocks (BZ_USE_MOCKS=1).
final class BedoonZahmaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // الاختبارات مكتوبة بالعربية (اللغة الافتراضية للمنتج) — نُجبر المحاكي على العربية و RTL.
        app.launchArguments += ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA", "-AppleTextDirection", "YES"]
        app.launch()
    }

    func testHomeShowsWhereToAndQuickActions() {
        XCTAssertTrue(app.staticTexts["وين رايح؟"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["مقاهيي"].exists)
        XCTAssertTrue(app.staticTexts["مطاعمي"].exists)
    }

    func testCafesFlowOpensListThenDetailsThenRouteOptions() {
        app.staticTexts["مقاهيي"].tap()
        XCTAssertTrue(app.staticTexts["مقاهٍ قريبة منك"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["≤ 5 دقائق"].exists)
        let firstCard = app.buttons.containing(.staticText, identifier: "محمصة سدر (تجريبي)").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        firstCard.tap()
        XCTAssertTrue(app.buttons["اذهب الآن"].waitForExistence(timeout: 5))
        app.buttons["اذهب الآن"].tap()
        XCTAssertTrue(app.staticTexts["بدون توقف"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["أسرع طريق"].exists)
        XCTAssertTrue(app.staticTexts["أقصر طريق"].exists)
        XCTAssertTrue(app.buttons["ابدأ"].exists)
    }

    func testSearchFlowShowsThreeRouteOptions() {
        app.staticTexts["وين رايح؟"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("البوليفارد")
        let result = app.buttons.containing(.staticText, identifier: "البوليفارد").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.buttons["ابدأ"].waitForExistence(timeout: 8))
        app.buttons["ابدأ"].tap()
        XCTAssertTrue(app.buttons["إنهاء"].waitForExistence(timeout: 5))
    }
}
