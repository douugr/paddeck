import UIKit

/// Touch surface: 1 finger moves, tap clicks, 2-finger tap right-clicks, 2 fingers scroll,
/// double-tap-and-drag drags, 3-finger swipes switch Spaces / open Mission Control.
/// The bottom strip has holdable left/right buttons.
final class TrackpadView: UIView {
    private let surface = UIView()
    private let hint = UILabel()
    private let leftButton = UIButton(type: .custom)
    private let rightButton = UIButton(type: .custom)

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

        hint.text = "Trackpad"
        hint.textColor = UIColor(white: 1, alpha: 0.12)
        hint.font = .systemFont(ofSize: 28, weight: .light)
        hint.textAlignment = .center
        surface.addSubview(hint)

        setup(leftButton, title: "Clique", tag: 0)
        setup(rightButton, title: "Clique direito", tag: 1)
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
        hint.frame = surface.bounds
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
    }

    override func touchesBegan(_ new: Set<UITouch>, with event: UIEvent?) {
        if touches.isEmpty {
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

    private func finish(_ ended: Set<UITouch>, cancelled: Bool) {
        touches.subtract(ended)
        guard touches.isEmpty else { return }
        surface.backgroundColor = Theme.surface

        let tap = !cancelled && CACurrentMediaTime() - start < tapMaxDuration && travel < tapMaxTravel
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
