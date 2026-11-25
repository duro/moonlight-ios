//
//  CaddyKeySender.swift
//  Sends key presses to the host through moonlight-common-c, the same call
//  KeyboardSupport.m uses for hardware keyboards (0x8000 | VK + modifier flags).
//  Requires `#import <Limelight.h>` in Moonlight-Bridging-Header.h.
//

import Foundation

final class CaddyKeySender {
    static let shared = CaddyKeySender()

    /// Serial queue so presses stay ordered and the main thread never blocks.
    private let queue = DispatchQueue(label: "caddy.keysender")
    /// Gap between key down and key up; matches the on-screen keyboard's 50 ms.
    private let pressDuration: useconds_t = 50_000

    private struct Mod { let flag: Int32; let vk: UInt16 }
    private static let modifierTable: [String: Mod] = [
        "shift": Mod(flag: MODIFIER_SHIFT, vk: 0x10),
        "ctrl":  Mod(flag: MODIFIER_CTRL,  vk: 0x11),
        "alt":   Mod(flag: MODIFIER_ALT,   vk: 0x12),
    ]

    /// Full press: modifiers down, key down, wait, key up, modifiers up.
    func press(_ button: CaddyButton) {
        guard let vk = button.virtualKey else { return }
        let mods = button.modifiers.compactMap { Self.modifierTable[$0.lowercased()] }
        queue.async { [pressDuration] in
            var flags: Int32 = 0
            for m in mods {
                flags |= m.flag
                Self.send(m.vk, down: true, flags: flags)
            }
            Self.send(vk, down: true, flags: flags)
            usleep(pressDuration)
            Self.send(vk, down: false, flags: flags)
            for m in mods.reversed() {
                flags &= ~m.flag
                Self.send(m.vk, down: false, flags: flags)
            }
        }
    }

    /// For "hold" buttons (e.g. SPACE fast-forward): key stays down until keyUp.
    func keyDown(_ button: CaddyButton) {
        guard let vk = button.virtualKey else { return }
        queue.async { Self.send(vk, down: true, flags: 0) }
    }

    func keyUp(_ button: CaddyButton) {
        guard let vk = button.virtualKey else { return }
        queue.async { Self.send(vk, down: false, flags: 0) }
    }

    private static func send(_ vk: UInt16, down: Bool, flags: Int32) {
        let code = Int16(bitPattern: 0x8000 | vk)
        let action = Int8(truncatingIfNeeded: down ? KEY_ACTION_DOWN : KEY_ACTION_UP)
        _ = LiSendKeyboardEvent(code, action, Int8(truncatingIfNeeded: flags))
    }
}
