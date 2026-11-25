//
//  CaddyOverlayView.swift
//  Floating draggable trigger + shortcut panel drawn above the Moonlight stream.
//  Touches outside the trigger and the open panel fall through to the stream.
//

import UIKit

@objc(CaddyOverlayView)
final class CaddyOverlayView: UIView {

    // MARK: Tunables
    private let triggerSize: CGFloat = 56
    private let edgeMargin: CGFloat = 8
    private let idleAlpha: CGFloat = 0.45
    // Panel geometry, modelled on TouchCaddy's Home screen (portrait grid, 12 columns).
    private let panelWidth: CGFloat = 380
    private let rowHeight: CGFloat = 72       // >= 60 pt thumb target
    private let minRowHeight: CGFloat = 40    // floor for short screens (iPhone landscape)
    private let buttonSpacing: CGFloat = 6
    private let panelPadding: CGFloat = 8
    private let positionKey = "CaddyTriggerPosition"

    // MARK: Views
    private let trigger = UIView()
    private let triggerIcon = UIImageView()
    private let panel = UIView()
    private var keyButtons: [CaddyKeyButton] = []
    private var panelRows: [[(view: CaddyKeyButton, span: Int)]] = []

    // Aim fade: while an aim button is held the panel goes nearly transparent.
    private var activeFaders = Set<ObjectIdentifier>()
    private var fadeRestore: DispatchWorkItem?
    private var isFaded = false
    private let fadeRestoreDelay: TimeInterval = 0.4   // bridges quick successive taps

    // Auto-hide: close the panel after this long with no interaction.
    private let autoHideDelay: TimeInterval = 8
    private var autoHideTimer: Timer?
    private var heldButtons = Set<ObjectIdentifier>()

    private let config: CaddyConfig
    private var isPanelOpen = false { didSet { updateTriggerAppearance() } }

    /// Saved trigger position: which edge it is snapped to and where along that edge (0...1).
    private enum Edge: String { case left, right, top, bottom }
    private var edge: Edge = .right
    private var edgeFraction: CGFloat = 0.5

    // MARK: Init

    @objc override convenience init(frame: CGRect) {
        self.init(frame: frame, config: CaddyConfig.loadBundled())
    }

    init(frame: CGRect, config: CaddyConfig) {
        self.config = config
        super.init(frame: frame)
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        loadPosition()
        buildTrigger()
        buildPanel()
        isHidden = true   // shown once the stream connects
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    @objc func show() {
        isHidden = false
        setNeedsLayout()
    }

    // MARK: Touch pass-through

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden else { return nil }
        if trigger.frame.contains(point) || (isPanelOpen && panel.frame.contains(point)) {
            return super.hitTest(point, with: event)
        }
        return nil
    }

    // MARK: Trigger

    private func buildTrigger() {
        trigger.frame = CGRect(x: 0, y: 0, width: triggerSize, height: triggerSize)
        trigger.layer.cornerRadius = triggerSize / 2
        trigger.backgroundColor = UIColor(white: 0.1, alpha: 0.85)
        trigger.layer.borderColor = UIColor(white: 1, alpha: 0.6).cgColor
        trigger.layer.borderWidth = 1.5
        trigger.accessibilityLabel = "Caddie shortcuts"
        trigger.isAccessibilityElement = true

        triggerIcon.image = UIImage(systemName: "figure.golf",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold))
        triggerIcon.tintColor = .white
        triggerIcon.contentMode = .center
        triggerIcon.frame = trigger.bounds
        triggerIcon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        trigger.addSubview(triggerIcon)

        let tap = UITapGestureRecognizer(target: self, action: #selector(triggerTapped))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(triggerPanned(_:)))
        tap.require(toFail: pan)   // a drag never counts as a tap
        trigger.addGestureRecognizer(tap)
        trigger.addGestureRecognizer(pan)
        addSubview(trigger)
        updateTriggerAppearance()
    }

    private func updateTriggerAppearance() {
        UIView.animate(withDuration: 0.2) {
            self.trigger.alpha = self.isPanelOpen ? 1.0 : self.idleAlpha
        }
    }

    @objc private func triggerTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        setPanelOpen(!isPanelOpen)
    }

    @objc private func triggerPanned(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            restartAutoHide()
            trigger.alpha = 1.0
            if isPanelOpen { panel.isHidden = true }
        case .changed:
            let t = g.translation(in: self)
            trigger.center = CGPoint(x: trigger.center.x + t.x, y: trigger.center.y + t.y)
            g.setTranslation(.zero, in: self)
        case .ended, .cancelled, .failed:
            snapToNearestEdge(from: trigger.center)
            savePosition()
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8,
                           initialSpringVelocity: 0.5, options: []) {
                self.layoutTrigger()
            } completion: { _ in
                if self.isPanelOpen {
                    self.layoutPanel()
                    self.panel.isHidden = false
                }
                self.updateTriggerAppearance()
            }
        default:
            break
        }
    }

    private var usableRect: CGRect {
        bounds.inset(by: safeAreaInsets).insetBy(dx: edgeMargin, dy: edgeMargin)
    }

    private func snapToNearestEdge(from p: CGPoint) {
        let r = usableRect
        let distances: [(Edge, CGFloat)] = [
            (.left, p.x - r.minX), (.right, r.maxX - p.x),
            (.top, p.y - r.minY), (.bottom, r.maxY - p.y),
        ]
        edge = distances.min { $0.1 < $1.1 }!.0
        switch edge {
        case .left, .right: edgeFraction = ((p.y - r.minY) / max(r.height, 1)).clamped(0, 1)
        case .top, .bottom: edgeFraction = ((p.x - r.minX) / max(r.width, 1)).clamped(0, 1)
        }
    }

    private func layoutTrigger() {
        let r = usableRect
        let h = triggerSize / 2
        var c: CGPoint
        switch edge {
        case .left:   c = CGPoint(x: r.minX + h, y: r.minY + edgeFraction * r.height)
        case .right:  c = CGPoint(x: r.maxX - h, y: r.minY + edgeFraction * r.height)
        case .top:    c = CGPoint(x: r.minX + edgeFraction * r.width, y: r.minY + h)
        case .bottom: c = CGPoint(x: r.minX + edgeFraction * r.width, y: r.maxY - h)
        }
        c.x = c.x.clamped(r.minX + h, r.maxX - h)
        c.y = c.y.clamped(r.minY + h, r.maxY - h)
        trigger.center = c
    }

    private func loadPosition() {
        if let d = UserDefaults.standard.dictionary(forKey: positionKey),
           let e = (d["edge"] as? String).flatMap(Edge.init(rawValue:)),
           let f = d["fraction"] as? Double {
            edge = e
            edgeFraction = CGFloat(f)
        }
        // Default: mid-height on the right edge, clear of GSPro's corner UI.
    }

    private func savePosition() {
        UserDefaults.standard.set(["edge": edge.rawValue, "fraction": Double(edgeFraction)],
                                  forKey: positionKey)
    }

    // MARK: Panel

    private func buildPanel() {
        panel.backgroundColor = CaddyTheme.panelBackground
        panel.layer.cornerRadius = 16
        panel.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        panel.layer.borderWidth = 1
        panel.isHidden = true

        panelRows = config.panelRows.map { row in
            row.map { cell in
                let kb = CaddyKeyButton(button: cell.button)
                kb.onPressChanged = { [weak self] b, pressing in
                    guard let self = self else { return }
                    self.keyPressChanged(b, pressing: pressing)
                    if b.button.fadesPanel { self.faderChanged(b, pressing: pressing) }
                }
                keyButtons.append(kb)
                panel.addSubview(kb)
                return (kb, cell.span)
            }
        }
        addSubview(panel)
    }

    private func setPanelOpen(_ open: Bool) {
        isPanelOpen = open
        restartAutoHide()
        if open {
            layoutPanel()
            panel.isHidden = false
            panel.alpha = 0
            panel.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            UIView.animate(withDuration: 0.15) {
                self.panel.alpha = 1
                self.panel.transform = .identity
            }
        } else {
            keyButtons.forEach { $0.cancelActivePress() }
            heldButtons.removeAll()
            fadeRestore?.cancel()
            activeFaders.removeAll()
            if isFaded { applyFade(false) }
            UIView.animate(withDuration: 0.12, animations: { self.panel.alpha = 0 }) { _ in
                if !self.isPanelOpen { self.panel.isHidden = true }
            }
        }
    }

    private func keyPressChanged(_ b: CaddyKeyButton, pressing: Bool) {
        if pressing { heldButtons.insert(ObjectIdentifier(b)) } else { heldButtons.remove(ObjectIdentifier(b)) }
        restartAutoHide()
    }

    /// Restart the idle countdown. While a key is held the countdown is paused.
    private func restartAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard isPanelOpen, heldButtons.isEmpty else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            guard let self = self, self.isPanelOpen, self.heldButtons.isEmpty else { return }
            self.setPanelOpen(false)
        }
    }

    private func faderChanged(_ b: CaddyKeyButton, pressing: Bool) {
        if pressing {
            activeFaders.insert(ObjectIdentifier(b))
            fadeRestore?.cancel()
            fadeRestore = nil
            applyFade(true)
        } else {
            activeFaders.remove(ObjectIdentifier(b))
            guard activeFaders.isEmpty else { applyFade(true); return }
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.activeFaders.isEmpty else { return }
                self.applyFade(false)
            }
            fadeRestore = work
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeRestoreDelay, execute: work)
        }
    }

    private func applyFade(_ faded: Bool) {
        isFaded = faded
        UIView.animate(withDuration: faded ? 0.15 : 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.panel.backgroundColor = faded ? CaddyTheme.panelBackground.withAlphaComponent(0.1) : CaddyTheme.panelBackground
            self.panel.layer.borderColor = UIColor(white: 1, alpha: faded ? 0.04 : 0.12).cgColor
            self.trigger.alpha = faded ? 0.15 : (self.isPanelOpen ? 1.0 : self.idleAlpha)
            for kb in self.keyButtons {
                let active = self.activeFaders.contains(ObjectIdentifier(kb))
                kb.alpha = kb.baseAlpha * (faded ? (active ? 0.5 : 0.12) : 1.0)
            }
        }
    }

    private func layoutPanel() {
        let r = usableRect
        let gap: CGFloat = 10
        let columns = CGFloat(max(config.layout.columns, 1))
        let rowCount = CGFloat(max(panelRows.count, 1))

        // Fit the panel's height to the screen, shrinking rows down to minRowHeight if needed.
        let chrome = 2 * panelPadding + (rowCount - 1) * buttonSpacing
        // iPads fit at full size; on an iPhone in landscape the rows shrink so all 7 fit on screen.
        let rowH = max(minRowHeight, min(rowHeight, (r.height - chrome) / rowCount))
        // Keep keys roughly in proportion when rows shrink, so they don't turn into thin strips.
        let width = panelWidth * max(rowH / rowHeight, 0.8)
        let s = CGSize(width: min(width, r.width), height: chrome + rowCount * rowH)

        let t = trigger.frame
        var origin: CGPoint
        switch edge {
        case .right:  origin = CGPoint(x: t.minX - gap - s.width, y: t.midY - s.height / 2)
        case .left:   origin = CGPoint(x: t.maxX + gap,           y: t.midY - s.height / 2)
        case .top:    origin = CGPoint(x: t.midX - s.width / 2,   y: t.maxY + gap)
        case .bottom: origin = CGPoint(x: t.midX - s.width / 2,   y: t.minY - gap - s.height)
        }
        origin.x = origin.x.clamped(r.minX, max(r.minX, r.maxX - s.width))
        origin.y = origin.y.clamped(r.minY, max(r.minY, r.maxY - s.height))
        panel.frame = CGRect(origin: origin, size: s)

        // Lay each row out on the column grid; spans in a row should add up to `columns`.
        let innerW = s.width - 2 * panelPadding
        let colW = (innerW - (columns - 1) * buttonSpacing) / columns
        for (i, row) in panelRows.enumerated() {
            var x = panelPadding
            let y = panelPadding + CGFloat(i) * (rowH + buttonSpacing)
            for cell in row {
                let span = CGFloat(cell.span)
                let w = span * colW + (span - 1) * buttonSpacing
                cell.view.frame = CGRect(x: x, y: y, width: w, height: rowH)
                x += w + buttonSpacing
            }
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTrigger()
        if isPanelOpen { layoutPanel() }
    }
}

// MARK: - Panel button

enum CaddyTheme {
    // TouchCaddy-style navy keys on a near-black panel.
    static let panelBackground = GSProTheme.background.withAlphaComponent(0.94)
    static let key = UIColor(red: 0.14, green: 0.27, blue: 0.41, alpha: 1)          // #24466A
    static let keyPressed = GSProTheme.accent
    static let keyBorder = UIColor(red: 0.20, green: 0.34, blue: 0.50, alpha: 1)
}

final class CaddyKeyButton: UIControl {
    let button: CaddyButton
    private let stack = UIStackView()
    private var iconPart: UIImageView?
    private var textPart: UILabel?
    private var repeatTimer: Timer?
    private var holding = false
    private var pressing = false
    /// Called with true on touch down and false on release, for buttons that fade the panel.
    var onPressChanged: ((CaddyKeyButton, Bool) -> Void)?
    private(set) var baseAlpha: CGFloat = 1

    private let repeatDelay: TimeInterval = 0.35
    private let repeatInterval: TimeInterval = 0.12

    init(button: CaddyButton) {
        self.button = button
        super.init(frame: .zero)
        layer.cornerRadius = 10
        backgroundColor = CaddyTheme.key
        layer.borderWidth = 1
        layer.borderColor = (button.practiceOnly ? UIColor.systemOrange : CaddyTheme.keyBorder).cgColor
        isEnabled = button.virtualKey != nil
        baseAlpha = isEnabled ? 1 : 0.35
        alpha = baseAlpha
        accessibilityLabel = button.label
        isAccessibilityElement = true
        accessibilityTraits = .button

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.isUserInteractionEnabled = false
        addSubview(stack)

        let iconView: UIImageView = {
            let v = UIImageView(image: UIImage(systemName: button.symbol) ?? UIImage(systemName: "questionmark.square"))
            v.tintColor = .white
            v.contentMode = .scaleAspectFit
            v.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            v.setContentCompressionResistancePriority(.required, for: .horizontal)
            return v
        }()
        let textView: UILabel = {
            let l = UILabel()
            l.text = button.label
            l.textColor = .white
            l.font = .systemFont(ofSize: 17, weight: .medium)
            l.textAlignment = .center
            l.numberOfLines = 2
            l.lineBreakMode = .byWordWrapping
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.6
            return l
        }()
        if button.display != "text" { iconPart = iconView }
        if button.display != "icon" { textPart = textView }

        switch button.display {
        case "icon":     stack.addArrangedSubview(iconView)
        case "textIcon": stack.addArrangedSubview(textView); stack.addArrangedSubview(iconView)
        case "iconText": stack.addArrangedSubview(iconView); stack.addArrangedSubview(textView)
        default:         stack.addArrangedSubview(textView)
        }

        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxW = bounds.width - 12

        // Text + icon keys (e.g. "Club Up +"): on narrow keys (iPhone) the icon would squeeze the
        // text into fragments, so drop the icon whenever the longest word can't sit beside it.
        if let icon = iconPart, let text = textPart {
            // Measure at 75% size: the label may shrink a little (minimumScaleFactor) before
            // the icon has to go. iPad keys (~75 pt) keep the icon; iPhone keys (~55 pt) drop it.
            let baseFont = text.font ?? .systemFont(ofSize: 17, weight: .medium)
            let font = baseFont.withSize(baseFont.pointSize * 0.75)
            let longestWord = (text.text ?? "").split(separator: " ")
                .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
                .max() ?? 0
            let iconW = icon.intrinsicContentSize.width
            icon.isHidden = longestWord + stack.spacing + iconW > maxW
        }
        let fit = stack.systemLayoutSizeFitting(CGSize(width: maxW, height: bounds.height),
                                                withHorizontalFittingPriority: .defaultLow,
                                                verticalFittingPriority: .fittingSizeLevel)
        let w = min(fit.width, maxW)
        stack.frame = CGRect(x: (bounds.width - w) / 2, y: 4, width: w, height: bounds.height - 8)
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? CaddyTheme.keyPressed : CaddyTheme.key }
    }

    @objc private func touchDown() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        pressing = true
        onPressChanged?(self, true)
        if button.hold {
            holding = true
            CaddyKeySender.shared.keyDown(button)
            return
        }
        CaddyKeySender.shared.press(button)
        if button.repeats {
            repeatTimer = Timer.scheduledTimer(withTimeInterval: repeatDelay, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: self.repeatInterval, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    CaddyKeySender.shared.press(self.button)
                }
            }
        }
    }

    @objc private func touchUp() { cancelActivePress() }

    func cancelActivePress() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        if pressing {
            pressing = false
            onPressChanged?(self, false)
        }
        if holding {
            holding = false
            CaddyKeySender.shared.keyUp(button)
        }
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}
