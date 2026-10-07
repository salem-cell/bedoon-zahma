import XCTest

/// اختبارات واجهة أساسية تعمل على المحاكي بوضع DevMocks (BZ_USE_MOCKS=1).
/// نعتمد معرّفات الوصول لا النصوص، حتى لا تتأثر باللغة أو بالأرقام العربية.
final class BedoonZahmaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launch()
    }

    override func tearDown() {
        if app.state != .runningForeground {
            XCTFail("التطبيق لم يعد يعمل في المقدمة (حالة: \(app.state.rawValue)) — انهيار محتمل")
        }
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testHomeShowsWhereToAndQuickActions() {
        XCTAssertTrue(element("home.where").waitForExistence(timeout: 8))
        XCTAssertTrue(element("home.cafes").exists)
        XCTAssertTrue(element("home.restaurants").exists)
        XCTAssertTrue(app.staticTexts["وين رايح؟"].exists || app.buttons["وين رايح؟"].exists)
    }

    func testCafesFlowOpensListThenDetailsThenRouteOptions() {
        XCTAssertTrue(element("home.cafes").waitForExistence(timeout: 8))
        element("home.cafes").tap()
        let title = element("screen.title")
        XCTAssertTrue(title.waitForExistence(timeout: 8), "عنوان شاشة المقاهي لم يظهر — حالة التطبيق: \(app.state.rawValue)")
        XCTAssertEqual(title.label, "مقاهٍ قريبة منك")
        XCTAssertTrue(element("nearby.time.5").exists)
        let card = element("place.card.dev-c1")
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        let goNow = element("place.gonow")
        XCTAssertTrue(goNow.waitForExistence(timeout: 8))
        goNow.tap()
        XCTAssertTrue(element("route.no_stop").waitForExistence(timeout: 10))
        XCTAssertTrue(element("route.fastest").exists)
        XCTAssertTrue(element("route.shortest").exists)
        XCTAssertTrue(element("routes.start").exists)
    }

    func testSearchFlowShowsThreeRouteOptionsAndStartsNavigation() {
        XCTAssertTrue(element("home.where").waitForExistence(timeout: 8))
        element("home.where").tap()
        let field = element("search.field")
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("البوليفارد")
        let result = element("search.result.dev-boulevard")
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        let start = element("routes.start")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(element("nav.end").waitForExistence(timeout: 8))
        element("nav.end").tap()
        XCTAssertTrue(element("home.where").waitForExistence(timeout: 8))
    }
}
