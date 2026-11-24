# GSPro Caddy overlay

A floating, draggable button over the stream that opens a TouchCaddy-style panel of GSPro
keyboard shortcuts. Keys go to the host through `LiSendKeyboardEvent`, the same path
`KeyboardSupport.m` uses for hardware keyboards, so nothing changes on the PC.

- `gspro-bindings.json`: every GSPro shortcut (from the in-game TAB overlay) plus the panel `layout`
  (rows on a 12-column grid). Edit this and rebuild to change the panel.
- `CaddyConfig.swift`: JSON model and the key-name to Windows virtual-key table.
- `CaddyKeySender.swift`: key down/up with modifiers on a serial queue.
- `CaddyOverlayView.swift`: trigger (drag, edge snap, saved position, touch pass-through) and panel.

Upstream touch points, kept small for easy merges:
- `StreamFrameViewController.m`: creates the overlay in `viewDidLoad`, shows it in `connectionStarted`.
- `Moonlight-Bridging-Header.h`: imports `<Limelight.h>`.
- `project.pbxproj`: adds this group to the iOS target; iOS bundle id `com.duroworx.gsprocaddy`, team `B9AH7Q59QL`.
- `Limelight-Info.plist`: display name "GSPro Caddy" so it sits beside stock Moonlight.
