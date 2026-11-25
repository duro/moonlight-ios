//
//  CaddyConfig.swift
//  GSPro Caddy overlay: button config loaded from the bundled gspro-bindings.json.
//

import Foundation

struct CaddyButton: Decodable {
    let id: String
    let label: String
    let symbol: String
    let key: String
    let modifiers: [String]
    let repeats: Bool
    let hold: Bool
    let practiceOnly: Bool
    /// How the button face is drawn: icon, text, textIcon (text then icon) or iconText.
    let display: String
    /// While held, fade the panel so the course behind it stays visible (aim buttons).
    let fadesPanel: Bool

    enum CodingKeys: String, CodingKey {
        case id, label, symbol, key, modifiers, hold, practiceOnly, display, fadesPanel
        case repeats = "repeat"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "questionmark.square"
        key = try c.decode(String.self, forKey: .key)
        modifiers = try c.decodeIfPresent([String].self, forKey: .modifiers) ?? []
        repeats = try c.decodeIfPresent(Bool.self, forKey: .repeats) ?? false
        hold = try c.decodeIfPresent(Bool.self, forKey: .hold) ?? false
        practiceOnly = try c.decodeIfPresent(Bool.self, forKey: .practiceOnly) ?? false
        display = try c.decodeIfPresent(String.self, forKey: .display) ?? "text"
        fadesPanel = try c.decodeIfPresent(Bool.self, forKey: .fadesPanel) ?? false
    }

    /// Windows virtual-key code, or nil if the key name is unknown / "TBD" (button renders disabled).
    var virtualKey: UInt16? { CaddyKeyMap.virtualKey(for: key) }
}

struct CaddyLayoutCell: Decodable {
    let id: String
    let span: Int
}

struct CaddyLayout: Decodable {
    let columns: Int
    let rows: [[CaddyLayoutCell]]
}

struct CaddyConfig: Decodable {
    let buttons: [CaddyButton]
    let layout: CaddyLayout

    /// Panel rows resolved to buttons. Unknown ids are skipped with a log line.
    var panelRows: [[(button: CaddyButton, span: Int)]] {
        let byId = Dictionary(buttons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return layout.rows.map { row in
            row.compactMap { cell in
                guard let b = byId[cell.id] else {
                    NSLog("[Caddy] layout references unknown button id %@", cell.id)
                    return nil
                }
                return (b, max(1, cell.span))
            }
        }
    }

    static let empty = CaddyConfig(buttons: [], layout: CaddyLayout(columns: 12, rows: []))

    static func loadBundled(named name: String = "gspro-bindings") -> CaddyConfig {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            NSLog("[Caddy] %@.json missing from bundle", name)
            return .empty
        }
        do {
            return try JSONDecoder().decode(CaddyConfig.self, from: data)
        } catch {
            NSLog("[Caddy] Failed to parse %@.json: %@", name, String(describing: error))
            return .empty
        }
    }
}

/// The one lookup table from config key names to Windows virtual-key codes.
enum CaddyKeyMap {
    static func virtualKey(for name: String) -> UInt16? {
        let n = name.uppercased()
        if let v = named[n] { return v }
        // Single letter or digit: VK code equals the ASCII code.
        if n.unicodeScalars.count == 1, let scalar = n.unicodeScalars.first,
           (65...90).contains(scalar.value) || (48...57).contains(scalar.value) {   // A-Z, 0-9
            return UInt16(scalar.value)
        }
        // F1...F24
        if n.hasPrefix("F"), let num = Int(n.dropFirst()), (1...24).contains(num) {
            return UInt16(0x70 + num - 1)
        }
        return nil
    }

    private static let named: [String: UInt16] = [
        "BACKSPACE": 0x08, "TAB": 0x09, "ENTER": 0x0D, "RETURN": 0x0D,
        "SHIFT": 0x10, "CTRL": 0x11, "CONTROL": 0x11, "ALT": 0x12,
        "ESC": 0x1B, "ESCAPE": 0x1B, "SPACE": 0x20,
        "PAGEUP": 0x21, "PAGEDOWN": 0x22, "END": 0x23, "HOME": 0x24,
        "LEFT": 0x25, "UP": 0x26, "RIGHT": 0x27, "DOWN": 0x28,
        "INSERT": 0x2D, "DELETE": 0x2E,
        "SEMICOLON": 0xBA, "PLUS": 0xBB, "EQUALS": 0xBB, "COMMA": 0xBC,
        "MINUS": 0xBD, "PERIOD": 0xBE, "SLASH": 0xBF, "BACKTICK": 0xC0,
        "LBRACKET": 0xDB, "BACKSLASH": 0xDC, "RBRACKET": 0xDD, "QUOTE": 0xDE,
    ]
}
