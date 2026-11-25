//
//  GSProTheme.swift
//  App-wide colors taken from gsprogolf.com: one signature blue on near-black.
//

import UIKit

@objc(GSProTheme)
final class GSProTheme: NSObject {
    static let accent        = UIColor(hex: 0x1A80C8)   // links, buttons, highlights
    static let accentPressed = UIColor(hex: 0x1568A3)
    static let background    = UIColor(hex: 0x0B0C10)   // page background
    static let surface       = UIColor(hex: 0x13141C)   // section / bar background
    static let text          = UIColor(hex: 0xE8EAF0)
    static let textSecondary = UIColor(hex: 0x8B929E)
    static let separator     = UIColor(white: 1, alpha: 0.09)

    /// Call once at launch, before any window is shown.
    @objc static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = surface
        nav.shadowColor = separator
        nav.titleTextAttributes = [.foregroundColor: text]
        nav.largeTitleTextAttributes = [.foregroundColor: text]
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = nav
        bar.scrollEdgeAppearance = nav
        bar.compactAppearance = nav
        bar.tintColor = accent

        let toolbar = UIToolbarAppearance()
        toolbar.configureWithOpaqueBackground()
        toolbar.backgroundColor = surface
        UIToolbar.appearance().standardAppearance = toolbar
        UIToolbar.appearance().tintColor = accent

        UISwitch.appearance().onTintColor = accent
        UISlider.appearance().minimumTrackTintColor = accent
        UISegmentedControl.appearance().selectedSegmentTintColor = accent
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: text], for: .normal)
        UIActivityIndicatorView.appearance().color = accent
    }

    /// Tint for the app's window(s).
    @objc static func style(window: UIWindow?) {
        window?.tintColor = accent
        window?.backgroundColor = background
        window?.overrideUserInterfaceStyle = .dark
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
