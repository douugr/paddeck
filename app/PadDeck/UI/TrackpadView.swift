import UIKit

/// Touch surface: 1 finger moves, tap clicks, 2-finger tap right-clicks, 2 fingers scroll,
/// double-tap-and-drag drags, 3-finger swipes switch Spaces / open Mission Control.
/// The bottom strip has holdable left/right buttons. An optional scroll strip on one edge
/// scrolls with a single finger (handy on iPhone, held in one hand).
final class TrackpadView: UIView {
    private let surface = UIView()
    private let hint = UILabel()
    private let leftButton = UIButton(type: .custom)
    private let rightButton = UIButton(type: .custom)

    // Scroll strip: one finger sliding along the edge scrolls vertically.
    private let strip = UIView()
    private let stripGrip = UIStackView()
    private var stripOn = true, stripLeft = false
    private var stripTouch: UITouch?

    private var touches = Set<UITouch>()
    private var maxFingers = 0
    private var start: CFTimeInterval = 0
    private var travel: CGFloat = 0
    private var rem = CGPoint.zero, scrollRem = CGPoint.zero
    private var swipe = CGPoint.zero
    private var swipeFired = false
    private var dragging = false
    private var secondTap = false   // a tap just happened and its click is on hold (tap-to-drag)
    private var clickTimer: Timer?

    // Momentum scrolling ("flick" with two fingers, like a Mac trackpad)
    private var scrollSamples: [(t: CFTimeInterval, x: Double, y: Double)] = []
    private var momentum = CGPoint.zero          // px per second, already scaled and signed
    private var momentumLink: CADisplayLink?
    private var momentumLast: CFTimeInterval = 0
    private var inertia = true

    private var pointerSpeed = 1.6, scrollSpeed = 1.5
    private var natural = true, tapToClick = true, tapToDrag = true

    private let tapMaxDuration: CFTimeInterval = 0.3
    private let tapMaxTravel: CGFloat = 10
    private let dragWindow: TimeInterval = 0.22

    private var conn: Connection { .shared }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true

        surface.backgroundColor = Theme.surface
        surface.layer.cornerRadius = 16
        surface.layer.cornerCurve = .continuous
        surface.isUserInteractionEnabled = false
        addSubview(surface)

        hint.text = String(localized: "Trackpad")
        hint.textColor = UIColor(white: 1, alpha: 0.12)
        hint.font = .systemFont(ofSize: 28, weight: .light)
        hint.textAlignment = .center
        surface.addSubview(hint)

        strip.backgroundColor = Theme.keyDark
        strip.layer.cornerRadius = 12
        strip.layer.cornerCurve = .continuous
        strip.isUserInteractionEnabled = false
        stripGrip.axis = .vertical
        stripGrip.alignment = .center
        stripGrip.spacing = 6
        let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        for name in ["chevron.up", "line.3.horizontal", "chevron.down"] {
            let iv = UIImageView(image: UIImage(systemName: name, withConfiguration: cfg))
            iv.tintColor = UIColor(white: 1, alpha: 0.25)
            stripGrip.addArrangedSubview(iv)
        }
        strip.addSubview(stripGrip)
        surface.addSubview(strip)
        strip.isAccessibilityElement = true
        strip.accessibilityLabel = String(localized: "Scroll strip")

        setup(leftButton, title: String(localized: "Click"), tag: 0)
        setup(rightButton, title: String(localized: "Right click"), tag: 1)

        stripOn = Prefs.scrollStrip
        stripLeft = Prefs.scrollStripLeft
        // Settings are a sheet over this view: follow changes right away.
        NotificationCenter.default.addObserver(self, selector: #selector(applyStripPrefs),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(_ b: UIButton, title: String, tag: Int) {
        b.tag = tag
        b.setTitle(title, for: .normal)
        b.setTitleColor(UIColor(white: 1, alpha: 0.6), for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        b.backgroundColor = Theme.surface
        b.layer.cornerRadius = 12
        b.layer.cornerCurve = .continuous
        b.addTarget(self, action: #selector(buttonDown(_:)), for: .touchDown)
        b.addTarget(self, action: #selector(buttonUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        addSubview(b)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = 8
        let buttonsH: CGFloat = Theme.isCompact(self) ? 44 : 56
        surface.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - buttonsH - gap)
        let stripW: CGFloat = Theme.isCompact(self) ? 40 : 52
        let inset: CGFloat = 6
        strip.isHidden = !stripOn
        strip.frame = CGRect(x: stripLeft ? inset : surface.bounds.width - stripW - inset, y: inset,
                             width: stripW, height: max(surface.bounds.height - inset * 2, 0))
        stripGrip.bounds.size = stripGrip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        stripGrip.center = CGPoint(x: strip.bounds.midX, y: strip.bounds.midY)
        // Keep the hint centred in the area that still moves the pointer.
        var free = surface.bounds
        if stripOn {
            free.size.width -= stripW + inset
            if stripLeft { free.origin.x += stripW + inset }
        }
        hint.frame = free
        let w = (bounds.width - gap) / 2
        let y = bounds.height - buttonsH
        leftButton.frame = CGRect(x: 0, y: y, width: w, height: buttonsH)
        rightButton.frame = CGRect(x: w + gap, y: y, width: w, height: buttonsH)
    }

    // MARK: Hold buttons

    @objc private func buttonDown(_ b: UIButton) {
        b.backgroundColor = Theme.keyActive
        conn.sendButton(b.tag == 0 ? .left : .right, .down)
    }

    @objc private func buttonUp(_ b: UIButton) {
        b.backgroundColor = Theme.surface
        conn.sendButton(b.tag == 0 ? .left : .right, .up)
    }

    // MARK: Gestures

    private func loadPrefs() {
        pointerSpeed = Prefs.pointerSpeed
        scrollSpeed = Prefs.scrollSpeed
        natural = Prefs.naturalScroll
        tapToClick = Prefs.tapToClick
        tapToDrag = Prefs.tapToDrag
        inertia = Prefs.inertialScroll
        applyStripPrefs()
    }

    /// Reads the strip settings; relayouts only when they changed.
    @objc private func applyStripPrefs() {
        let on = Prefs.scrollStrip, left = Prefs.scrollStripLeft
        guard on != stripOn || left != stripLeft else { return }
        stripOn = on
        stripLeft = left
        if Thread.isMainThread { setNeedsLayout() } else { DispatchQueue.main.async { self.setNeedsLayout() } }
    }

    private func stripContains(_ t: UITouch) -> Bool {
        guard stripOn, !strip.isHidden else { return false }
        // A little extra margin on the inner side makes the edge easy to hit.
        let r = surface.convert(strip.frame, to: self).insetBy(dx: -6, dy: 0)
        return r.contains(t.location(in: self))
    }

    override func touchesBegan(_ new: Set<UITouch>, with event: UIEvent?) {
        stopMomentum()   // touching the trackpad stops a flick, like on the Mac
        if stripTouch != nil { return }   // the strip owns the gesture until that finger lifts
        if touches.isEmpty {
            loadPrefs()
            if clickTimer == nil, let t = new.first(where: stripContains) {
                stripTouch = t
                scrollSamples.removeAll()
                scrollRem = .zero
                strip.backgroundColor = Theme.keyActive
                return
            }
        }
        if touches.isEmpty {
            scrollSamples.removeAll()
            loadPrefs()
            maxFingers = 0
            start = CACurrentMediaTime()
            travel = 0
            swipe = .zero
            swipeFired = false
            rem = .zero
            scrollRem = .zero
            if let t = clickTimer {
                t.invalidate()
                clickTimer = nil
                secondTap = true
            }
        }
        for t in new where surface.frame.contains(t.location(in: self)) { touches.insert(t) }
        maxFingers = max(maxFingers, touches.count)
        if secondTap && maxFingers > 1 {
            secondTap = false               // not a double tap: deliver the held click
            conn.sendButton(.left, .press)
        }
        surface.backgroundColor = Theme.surfaceActive
    }

    private func averageDelta() -> CGPoint {
        guard !touches.isEmpty else { return .zero }
        var sum = CGPoint.zero
        for t in touches {
            let a = t.location(in: self), p = t.previousLocation(in: self)
            sum.x += a.x - p.x
            sum.y += a.y - p.y
        }
        return CGPoint(x: sum.x / CGFloat(touches.count), y: sum.y / CGFloat(touches.count))
    }

    override func touchesMoved(_ moved: Set<UITouch>, with event: UIEvent?) {
        if let t = stripTouch {
            guard moved.contains(t) else { return }
            let dy = t.location(in: self).y - t.previousLocation(in: self).y
            // A bit faster than two fingers: the strip is short and used with the thumb.
            let v = Double(dy) * scrollSpeed * 1.5 * (natural ? 1 : -1)
            let fy = v + scrollRem.y
            let iy = Int(fy.rounded())
            scrollRem.y = fy - Double(iy)
            if iy != 0 { conn.sendScroll(dy: iy, dx: 0) }
            let now = CACurrentMediaTime()
            scrollSamples.append((now, 0, v))
            scrollSamples.removeAll { now - $0.t > 0.1 }
            return
        }
        guard !touches.isEmpty else { return }
        let d = averageDelta()
        let dist = hypot(d.x, d.y)
        travel += dist

        if touches.count == 1 && maxFingers == 1 {
            if secondTap && !dragging && travel > 6 {
                dragging = true
                conn.sendButton(.left, .down)
            }
            let gain = pointerSpeed * min(1 + Double(dist) * 0.08, 4)
            let fx = Double(d.x) * gain + rem.x, fy = Double(d.y) * gain + rem.y
            let ix = Int(fx.rounded()), iy = Int(fy.rounded())
            rem = CGPoint(x: fx - Double(ix), y: fy - Double(iy))
            conn.sendMove(dx: ix, dy: iy)
        } else if touches.count == 2 && maxFingers == 2 {
            guard travel >= 4 else { return }   // keep two-finger taps clean
            let sign: Double = natural ? 1 : -1
            let fy = Double(d.y) * scrollSpeed * sign + scrollRem.y
            let fx = Double(d.x) * scrollSpeed * sign + scrollRem.x
            let iy = Int(fy.rounded()), ix = Int(fx.rounded())
            scrollRem = CGPoint(x: fx - Double(ix), y: fy - Double(iy))
            conn.sendScroll(dy: iy, dx: ix)
            let now = CACurrentMediaTime()
            scrollSamples.append((now, Double(d.x) * scrollSpeed * sign, Double(d.y) * scrollSpeed * sign))
            scrollSamples.removeAll { now - $0.t > 0.1 }
        } else if touches.count == 3 && !swipeFired {
            swipe.x += d.x
            swipe.y += d.y
            var code: Int?
            if swipe.x < -80 { code = Keys.right }        // fingers left → next Space
            else if swipe.x > 80 { code = Keys.left }
            else if swipe.y < -60 { code = Keys.up }      // Mission Control
            else if swipe.y > 60 { code = Keys.down }     // App Exposé
            if let c = code {
                swipeFired = true
                conn.sendKey(c, mods: .ctrl)
            }
        }
    }

    override func touchesEnded(_ ended: Set<UITouch>, with event: UIEvent?) { finish(ended, cancelled: false) }
    override func touchesCancelled(_ c: Set<UITouch>, with event: UIEvent?) { finish(c, cancelled: true) }

    // MARK: Momentum

    private func startMomentum() {
        let now = CACurrentMediaTime()
        // Speed of the last ~100 ms of the gesture; a pause before lifting means no flick.
        guard let first = scrollSamples.first, let last = scrollSamples.last, now - last.t < 0.06 else { return }
        let span = max(now - first.t, 1.0 / 60)
        let vx = scrollSamples.reduce(0) { $0 + $1.x } / span
        let vy = scrollSamples.reduce(0) { $0 + $1.y } / span
        guard hypot(vx, vy) > 250 else { return }
        momentum = CGPoint(x: vx, y: vy)
        scrollRem = .zero
        momentumLast = now
        let link = CADisplayLink(target: self, selector: #selector(momentumTick(_:)))
        link.add(to: .main, forMode: .common)
        momentumLink = link
    }

    @objc private func momentumTick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = min(max(now - momentumLast, 0), 0.05)
        momentumLast = now
        // Friction close to macOS: speed drops ~5% every 1/60 s.
        let decay = pow(0.95, dt * 60)
        momentum = CGPoint(x: momentum.x * decay, y: momentum.y * decay)
        guard hypot(momentum.x, momentum.y) > 30 else { stopMomentum(); return }
        let fx = Double(momentum.x) * dt + scrollRem.x, fy = Double(momentum.y) * dt + scrollRem.y
        let ix = Int(fx.rounded()), iy = Int(fy.rounded())
        scrollRem = CGPoint(x: fx - Double(ix), y: fy - Double(iy))
        conn.sendScroll(dy: iy, dx: ix)
    }

    private func stopMomentum() {
        momentumLink?.invalidate()
        momentumLink = nil
        momentum = .zero
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { stopMomentum() }
    }

    private func finish(_ ended: Set<UITouch>, cancelled: Bool) {
        if let t = stripTouch {
            guard ended.contains(t) else { return }
            stripTouch = nil
            strip.backgroundColor = Theme.keyDark
            if !cancelled && inertia { startMomentum() }
            return
        }
        touches.subtract(ended)
        guard touches.isEmpty else { return }
        surface.backgroundColor = Theme.surface

        let tap = !cancelled && CACurrentMediaTime() - start < tapMaxDuration && travel < tapMaxTravel
        if maxFingers == 2 && !tap && !cancelled && inertia { startMomentum() }
        if dragging {
            dragging = false
            secondTap = false
            conn.sendButton(.left, .up)
            return
        }
        if secondTap {
            secondTap = false
            conn.sendButton(.left, .press)               // the held first click
            if tap { conn.sendButton(.left, .press) }    // second click → double click on the Mac
            return
        }
        guard tap, tapToClick, maxFingers > 0 else { return }
        switch maxFingers {
        case 1:
            if tapToDrag {
                clickTimer = Timer.scheduledTimer(withTimeInterval: dragWindow, repeats: false) { [weak self] _ in
                    self?.clickTimer = nil
                    self?.conn.sendButton(.left, .press)
                }
            } else {
                conn.sendButton(.left, .press)
            }
        case 2: conn.sendButton(.right, .press)
        case 3: conn.sendButton(.middle, .press)
        default: break
        }
    }
}
