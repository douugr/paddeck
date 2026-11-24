import UIKit
import SwiftUI
import Combine

/// Invisible responder that forwards the iOS keyboard (accents, emoji, dictation) to the Mac.
final class TextSink: UIView, UIKeyInput {
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardAppearance: UIKeyboardAppearance = Theme.isLight ? .light : .dark

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }   // keeps backspace working
    func insertText(_ text: String) { Connection.shared.sendText(text) }
    func deleteBackward() { Connection.shared.sendKey(Keys.delete) }
}

/// Connected screen: trackpad + keyboard, or the shortcut deck.
final class MainViewController: UIViewController {
    private let bar = UIView()
    private let dot = UIView()
    private let statusLabel = UILabel()
    private let mode = UISegmentedControl(items: [String(localized: "Trackpad"), String(localized: "Shortcuts")])
    private let keyboardButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let leaveButton = UIButton(type: .system)
    private let trackpad = TrackpadView()
    private let keyboard = KeyboardView()
    private let deck = DeckView()
    private let sink = TextSink()
    private var subs = Set<AnyCancellable>()

    override var preferredStatusBarStyle: UIStatusBarStyle { Theme.isLight ? .darkContent : .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        bar.backgroundColor = Theme.bar
        view.addSubview(bar)
        dot.layer.cornerRadius = 5
        bar.addSubview(dot)
        statusLabel.textColor = Theme.text(0.75)
        statusLabel.font = .systemFont(ofSize: 15)
        bar.addSubview(statusLabel)

        mode.selectedSegmentIndex = 0
        mode.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        bar.addSubview(mode)

        setup(keyboardButton, symbol: "keyboard", label: String(localized: "Show or hide the keyboard"), action: #selector(toggleKeyboard))
        setup(settingsButton, symbol: "gearshape", label: String(localized: "Settings"), action: #selector(openSettings))
        setup(leaveButton, symbol: "rectangle.portrait.and.arrow.right", label: String(localized: "Switch Mac"), action: #selector(leave))

        view.addSubview(trackpad)
        keyboard.onSystemKeyboard = { [weak self] in self?.toggleSystemKeyboard() }
        view.addSubview(keyboard)
        deck.isHidden = true
        deck.onEdit = { [weak self] i in self?.editSlot(i) }
        view.addSubview(deck)
        sink.inputAssistantItem.leadingBarButtonGroups = []
        sink.inputAssistantItem.trailingBarButtonGroups = []
        view.addSubview(sink)

        let c = Connection.shared
        Publishers.CombineLatest3(c.$state, c.$macName, c.$viaUSB)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, name, usb in self?.showStatus(state, name, usb) }
            .store(in: &subs)
    }

    private func setup(_ b: UIButton, symbol: String, label: String, action: Selector) {
        b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)), for: .normal)
        b.tintColor = Theme.accent
        b.accessibilityLabel = label
        b.addTarget(self, action: action, for: .touchUpInside)
        bar.addSubview(b)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = Prefs.keepAwake
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let compact = Theme.isCompact(view)
        let barH: CGFloat = 48, pad: CGFloat = compact ? 8 : 10

        bar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: safe.minY + barH)
        let barY = safe.minY
        dot.frame = CGRect(x: safe.minX + 14, y: barY + barH / 2 - 5, width: 10, height: 10)
        var x = safe.maxX - 6
        for b in [leaveButton, settingsButton, keyboardButton] {
            x -= 44
            b.frame = CGRect(x: x, y: barY + 2, width: 44, height: 44)
        }
        // The selector stays centered but never reaches the buttons or the status dot.
        let buttonsLeft = (keyboardButton.isHidden ? settingsButton.frame.minX : keyboardButton.frame.minX) - 10
        let half = min(safe.midX - (dot.frame.maxX + 10), buttonsLeft - safe.midX)
        let narrowBar = safe.width < 500
        setModeStyle(icons: narrowBar)
        let modeW = min(narrowBar ? 120 : 300, max(0, half * 2))
        mode.frame = CGRect(x: safe.midX - modeW / 2, y: barY + 8, width: modeW, height: 32)
        statusLabel.isHidden = narrowBar
        statusLabel.frame = CGRect(x: dot.frame.maxX + 8, y: barY, width: max(0, mode.frame.minX - dot.frame.maxX - 16), height: barH)

        let content = CGRect(x: safe.minX + pad, y: barY + barH + pad,
                             width: safe.width - pad * 2, height: safe.maxY - (barY + barH + pad) - pad)
        deck.frame = content

        let showKb = Prefs.showKeyboard
        let portraitPhone = compact && content.height > content.width
        // iPhone in portrait: rows about as tall as the iOS keyboard's; the rest goes to the trackpad.
        let kbH = showKb ? (portraitPhone ? min(floor(content.height * 0.4), 4 * 54 + 3 * 5)
                                          : floor(content.height * 0.52)) : 0
        let padH = content.height - kbH - (showKb ? pad : 0)
        keyboard.isHidden = !showKb || !deck.isHidden
        if Prefs.keyboardOnTop {
            keyboard.frame = CGRect(x: content.minX, y: content.minY, width: content.width, height: kbH)
            trackpad.frame = CGRect(x: content.minX, y: content.maxY - padH, width: content.width, height: padH)
        } else {
            keyboard.frame = CGRect(x: content.minX, y: content.maxY - kbH, width: content.width, height: kbH)
            trackpad.frame = CGRect(x: content.minX, y: content.minY, width: content.width, height: padH)
        }
    }

    private var modeIcons: Bool?

    /// Words on wide bars, symbols on narrow ones.
    private func setModeStyle(icons: Bool) {
        guard icons != modeIcons else { return }
        modeIcons = icons
        let items: [(String, String)] = [(String(localized: "Trackpad"), "hand.point.up.left"), (String(localized: "Shortcuts"), "square.grid.3x3.fill")]
        for (i, item) in items.enumerated() {
            if icons {
                let image = UIImage(systemName: item.1)
                image?.accessibilityLabel = item.0
                mode.setImage(image, forSegmentAt: i)
            } else {
                mode.setTitle(item.0, forSegmentAt: i)
            }
        }
    }

    private func showStatus(_ state: Connection.State, _ name: String?, _ usb: Bool) {
        switch state {
        case .connected:
            dot.backgroundColor = Theme.ok
            statusLabel.text = usb ? String(localized: "\(name ?? "Mac") · cable") : name
        case .connecting:
            dot.backgroundColor = Theme.warn
            statusLabel.text = String(localized: "Reconnecting…")
        case .idle:
            dot.backgroundColor = Theme.off
            statusLabel.text = String(localized: "Disconnected")
        }
    }

    // MARK: Actions

    @objc private func modeChanged() {
        let showDeck = mode.selectedSegmentIndex == 1
        deck.isHidden = !showDeck
        trackpad.isHidden = showDeck
        keyboardButton.isHidden = showDeck
        sink.resignFirstResponder()
        view.setNeedsLayout()
    }

    @objc private func toggleKeyboard() {
        Prefs.showKeyboard.toggle()
        UIView.animate(withDuration: 0.2) {
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }

    private func toggleSystemKeyboard() {
        if sink.isFirstResponder { sink.resignFirstResponder() } else { sink.becomeFirstResponder() }
    }

    @objc private func openSettings() {
        let host = UIHostingController(rootView: SettingsView { [weak self] in
            self?.dismiss(animated: true)
            UIApplication.shared.isIdleTimerDisabled = Prefs.keepAwake
            self?.deck.reload()
            self?.view.setNeedsLayout()
            // A new color profile rebuilds the screen (RootViewController listens for this).
            if Theme.reload() { NotificationCenter.default.post(name: Theme.changed, object: nil) }
        })
        host.modalPresentationStyle = .formSheet
        present(host, animated: true)
    }

    @objc private func leave() {
        sink.resignFirstResponder()
        Connection.shared.disconnect()   // the root goes back to the connect screen
    }

    private func editSlot(_ i: Int) {
        let editor = SlotEditorView(slot: Deck.shared[i]) { [weak self] result in
            self?.dismiss(animated: true)
            switch result {
            case .save(let slot): Deck.shared[i] = slot
            case .delete: Deck.shared[i] = nil
            case .cancel: return
            }
            self?.deck.reload()
        }
        let host = UIHostingController(rootView: editor)
        host.modalPresentationStyle = .formSheet
        present(host, animated: true)
    }
}
