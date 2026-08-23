import XCTest
@testable import Portfolio

final class ThemeAccessibilityTests: XCTestCase {
    func testThemeGalleryContainsAllLightDarkAndMonochromeVariants() {
        XCTAssertEqual(AppTheme.all.count, 17)
        XCTAssertEqual(AppTheme.all.map(\.id).count, Set(AppTheme.all.map(\.id)).count)
        XCTAssertEqual(AppTheme.all.filter { $0.id.hasPrefix("monochrome") }.count, 5)
        XCTAssertTrue(AppTheme.all.allSatisfy { $0.canvasLight != $0.canvasDark })
        XCTAssertTrue(AppTheme.all.allSatisfy { $0.cardLight != $0.cardDark })
    }

    func testMonochromeThemesHaveExactlyOneChromaticAccent() {
        let monochromes = AppTheme.all.filter { $0.id.hasPrefix("monochrome") }
        for theme in monochromes {
            let chromatic = theme.accents.filter { hex in
                let red = (hex >> 16) & 0xFF
                let green = (hex >> 8) & 0xFF
                let blue = hex & 0xFF
                return red != green || green != blue
            }
            XCTAssertEqual(chromatic.count, 1, "\(theme.id) should have one accent color")
            XCTAssertEqual(theme.positive >> 16 & 0xFF, theme.positive >> 8 & 0xFF)
            XCTAssertEqual(theme.negative >> 16 & 0xFF, theme.negative >> 8 & 0xFF)
        }
    }

    func testAccentTextContrastIsReadable() {
        for theme in AppTheme.all {
            for (accent, ink) in zip(theme.accents, theme.inkOnAccents) {
                XCTAssertGreaterThanOrEqual(AppTheme.contrastRatio(accent, ink), 3.0,
                                            "Low contrast in \(theme.id)")
            }
        }
    }

    func testAppearanceModeSupportsSystemLightAndDark() {
        XCTAssertEqual(AppAppearanceMode.allCases.count, 3)
        XCTAssertNil(AppAppearanceMode.system.colorScheme)
        XCTAssertEqual(AppAppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppAppearanceMode.dark.colorScheme, .dark)
    }
}
