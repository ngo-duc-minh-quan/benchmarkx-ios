import XCTest
import UIKit
@testable import BenchmarkX

final class ThemeTests: XCTestCase {
    private func components(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    func testHexWithHashBecomesOpaqueColor() {
        let c = components(UIColor(hex: "#FFD700"))

        XCTAssertEqual(c.r, 255.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.g, 215.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.b, 0, accuracy: 0.001)
        XCTAssertEqual(c.a, 1, accuracy: 0.001)
    }

    func testHexAcceptsLowercaseAndMissingHash() {
        let c = components(UIColor(hex: "00d2ff"))

        XCTAssertEqual(c.r, 0, accuracy: 0.001)
        XCTAssertEqual(c.g, 210.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.b, 1, accuracy: 0.001)
    }

    func testHexWithAlpha() {
        // RN bgGlass: rgba(13, 27, 46, 0.85)
        let c = components(UIColor(hex: "#0D1B2E", alpha: 0.85))

        XCTAssertEqual(c.r, 13.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.g, 27.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.b, 46.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.a, 0.85, accuracy: 0.001)
    }
}
