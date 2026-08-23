import XCTest

/// Valódi rendszer-görgetéssel őrzi a négy főfül reszponzivitását.
///
/// Nem képernyőképet hasonlít: a rendszer saját scroll-deceleration
/// signpostját méri, ezért az a regresszió is látszik, amikor a felület
/// helyes marad, csak képkockákat veszít.
final class ScrollPerformanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("-ui-scroll-performance-test")
        app.launch()
    }

    func testEveryMainTabCanScroll() throws {
        for title in ["Portfólió", "Hírek", "Kiadások", "Beállítások"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 8), "Hiányzó fül: \(title)")
            tab.tap()

            let scroller = firstScrollableElement()
            XCTAssertTrue(scroller.waitForExistence(timeout: 8),
                          "Nincs görgethető tartalom ezen a fülön: \(title)")
            scroller.swipeUp(velocity: .fast)
            scroller.swipeDown(velocity: .fast)
        }
    }

    /// A Kiadások tartalma függőleges lista. Egy vízszintes húzás nem tolhatja
    /// el az egész kártyaoszlopot, és nem válthat át rejtett oldalirányú
    /// görgetésre.
    func testExpensesContentStaysHorizontallyLocked() throws {
        let expenses = app.tabBars.buttons["Kiadások"]
        XCTAssertTrue(expenses.waitForExistence(timeout: 8))
        expenses.tap()

        let content = app.descendants(matching: .any)
            .matching(identifier: "expenses-scroll-content").firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 8))
        let originalX = content.frame.minX

        content.swipeRight(velocity: .slow)
        XCTAssertEqual(content.frame.minX, originalX, accuracy: 1)
        content.swipeLeft(velocity: .slow)
        XCTAssertEqual(content.frame.minX, originalX, accuracy: 1)
    }

    func testSettingsScrollDecelerationPerformance() throws {
        let settings = app.tabBars.buttons["Beállítások"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let scroller = firstScrollableElement()
        XCTAssertTrue(scroller.waitForExistence(timeout: 8))

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric],
                options: options) {
            scroller.swipeUp(velocity: .fast)
            scroller.swipeDown(velocity: .fast)
        }
    }

    /// A Portfólió fül első görgetését méri, miközben a közös vagyon-grafikon
    /// először megjelenik. Ez védi ki, hogy egy későbbi rajzolási animáció
    /// ismét a felület fő szálán, darabonként építse fel a görbéket.
    func testPortfolioChartInitialScrollPerformance() throws {
        let portfolio = app.tabBars.buttons["Portfólió"]
        XCTAssertTrue(portfolio.waitForExistence(timeout: 8))
        portfolio.tap()

        let scroller = firstScrollableElement()
        XCTAssertTrue(scroller.waitForExistence(timeout: 8))

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric],
                options: options) {
            scroller.swipeUp(velocity: .fast)
            scroller.swipeDown(velocity: .fast)
        }
    }

    /// Külön választja a tartós renderelési költséget az induláskor befejeződő
    /// hálózati/iCloud feladatoktól. Ha ez sima, de a fenti nem, akkor nem a
    /// List rajzolása, hanem egy háttérfeladat főszálra visszatérése a hitch.
    func testSettingsSettledScrollPerformance() throws {
        let settings = app.tabBars.buttons["Beállítások"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let scroller = firstScrollableElement()
        XCTAssertTrue(scroller.waitForExistence(timeout: 8))
        sleep(15)
        scroller.swipeUp(velocity: .fast)
        scroller.swipeDown(velocity: .fast)

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric],
                options: options) {
            scroller.swipeUp(velocity: .fast)
            scroller.swipeDown(velocity: .fast)
        }
    }

    private func firstScrollableElement() -> XCUIElement {
        if app.collectionViews.firstMatch.exists { return app.collectionViews.firstMatch }
        if app.tables.firstMatch.exists { return app.tables.firstMatch }
        return app.scrollViews.firstMatch
    }
}
