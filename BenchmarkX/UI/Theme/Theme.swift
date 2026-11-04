import UIKit

/// Design tokens ported from the RN app (constants/theme.ts and tierConfig in lib/scoreCalculator.ts).
enum Theme {
    enum Colors {
        static let primary = UIColor(hex: "#00D2FF")
        static let secondary = UIColor(hex: "#7B2FFF")
        static let accent = UIColor(hex: "#FF6B35")
        static let danger = UIColor(hex: "#FF3B3B")
        static let success = UIColor(hex: "#00FF88")
        static let warning = UIColor(hex: "#FFB800")

        static let bgDark = UIColor(hex: "#050A18")
        static let bgCard = UIColor(hex: "#0D1B2E")
        static let bgGlass = UIColor(hex: "#0D1B2E", alpha: 0.85)

        enum Text {
            static let primary = UIColor(hex: "#FFFFFF")
            static let secondary = UIColor(hex: "#FFFFFF", alpha: 0.7)
            static let muted = UIColor(hex: "#FFFFFF", alpha: 0.4)
            static let neon = UIColor(hex: "#00D2FF")
        }

        enum Border {
            static let `default` = UIColor(hex: "#00D2FF", alpha: 0.15)
            static let glow = UIColor(hex: "#00D2FF", alpha: 0.4)
            static let card = UIColor(hex: "#7B2FFF", alpha: 0.2)
        }

        static func tier(_ tier: Tier) -> UIColor {
            switch tier {
            case .S: return UIColor(hex: "#FFD700")
            case .A: return UIColor(hex: "#00E676")
            case .B: return UIColor(hex: "#00D4FF")
            case .C: return UIColor(hex: "#9E9E9E")
            }
        }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum BorderRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let full: CGFloat = 9999
    }

    enum FontSize {
        static let xs: CGFloat = 11
        static let sm: CGFloat = 13
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 40
        static let hero: CGFloat = 56
    }
}

extension UIColor {
    /// `hex` is "#RRGGBB" or "RRGGBB". Anything else is a programming error: it asserts in debug, black in release.
    convenience init(hex: String, alpha: CGFloat = 1) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        assert(digits.count == 6, "Expected a 6 digit hex color, got \(hex)")
        let value = UInt64(digits, radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}
