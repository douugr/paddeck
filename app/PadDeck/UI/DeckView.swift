import UIKit

/// A deck button: title + subtitle (or a symbol for media keys). Empty slots show a dashed "+".
private final class DeckButton: UIControl {
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let icon = UIImageView()
    let dash = CAShapeLayer()
    var baseColor: UIColor = .clear

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.numberOfLines = 2
        subtitleLabel.textColor = UIColor(white: 1, alpha: 0.65)
        subtitleLabel.textAlignment = .center
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        for v in [titleLabel, subtitleLabel, icon] as [UIView] {
            v.isUserInteractionEnabled = false
            addSubview(v)
        }
        dash.fillColor = UIColor.clear.cgColor
        dash.strokeColor = Theme.text(0.22).cgColor
        dash.lineWidth = 2
        dash.lineDashPattern = [8, 6]
        layer.addSublayer(dash)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let compact = b.height < 90
        titleLabel.font = .systemFont(ofSize: compact ? 15 : 21, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: compact ? 11 : 15)
        let hasIcon = icon.image != nil
        let iconSide = min(b.height * 0.28, 34)
        icon.frame = CGRect(x: (b.width - iconSide) / 2, y: b.height * 0.18, width: iconSide, height: iconSide)
        let titleTop = hasIcon ? icon.frame.maxY + 4 : b.height / 2 - (compact ? 22 : 30)
        titleLabel.frame = CGRect(x: 8, y: titleTop, width: b.width - 16, height: compact ? 34 : 40)
        subtitleLabel.frame = CGRect(x: 8, y: titleLabel.frame.maxY, width: b.width - 16, height: compact ? 14 : 22)
        subtitleLabel.isHidden = hasIcon
        dash.frame = b
        dash.path = UIBezierPath(roundedRect: b.insetBy(dx: 1, dy: 1), cornerRadius: 16).cgPath
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? baseColor.withAlphaComponent(0.6) : baseColor
            transform = isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
        }
    }

    func show(_ slot: Slot?) {
        dash.isHidden = slot != nil
        if let slot = slot {
            baseColor = Theme.deckColors[min(max(slot.color, 0), Theme.deckColors.count - 1)]
            titleLabel.text = slot.title
            titleLabel.textColor = .white
            subtitleLabel.text = slot.subtitle
            icon.image = slot.action == .media ? MediaKey(rawValue: slot.value).flatMap { UIImage(systemName: $0.symbol) } : nil
        } else {
            baseColor = .clear
            titleLabel.text = "+"
            titleLabel.textColor = Theme.text(0.3)
            subtitleLabel.text = ""
            icon.image = nil
        }
        backgroundColor = baseColor
        setNeedsLayout()
    }
}

/// Lets page swipes start on top of buttons.
private final class PagingScroll: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

/// Paged grid of shortcut buttons: 5×3 on iPad, 3×5 on iPhone. Tap runs, hold edits.
final class DeckView: UIView, UIScrollViewDelegate {
    var onEdit: ((Int) -> Void)?

    private let scroll = PagingScroll()
    private let pager = UIPageControl()
    private var buttons: [DeckButton] = []
    private let feedback = UIImpactFeedbackGenerator(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.delaysContentTouches = false
        scroll.delegate = self
        addSubview(scroll)

        pager.numberOfPages = Deck.pages
        pager.isUserInteractionEnabled = false
        addSubview(pager)

        for i in 0..<Deck.count {
            let b = DeckButton()
            b.tag = i
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
            lp.minimumPressDuration = 0.6
            b.addGestureRecognizer(lp)
            scroll.addSubview(b)
            buttons.append(b)
        }
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    func reload() {
        for b in buttons { b.show(Deck.shared[b.tag]) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pagerH: CGFloat = 28
        scroll.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - pagerH)
        pager.frame = CGRect(x: 0, y: bounds.height - pagerH, width: bounds.width, height: pagerH)
        let pw = scroll.bounds.width, ph = scroll.bounds.height
        scroll.contentSize = CGSize(width: pw * CGFloat(Deck.pages), height: ph)

        let portraitish = Theme.isCompact(self) && ph > pw
        let cols = portraitish ? 3 : 5, rows = portraitish ? 5 : 3
        let gap: CGFloat = Theme.isCompact(self) ? 10 : 14, margin: CGFloat = 12
        let w = (pw - margin * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let h = (ph - margin * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows)
        for b in buttons {
            let page = b.tag / Deck.perPage, j = b.tag % Deck.perPage
            let col = j % cols, row = j / cols
            b.transform = .identity
            b.frame = CGRect(x: CGFloat(page) * pw + margin + CGFloat(col) * (w + gap),
                             y: margin + CGFloat(row) * (h + gap), width: w, height: h)
        }
        scroll.contentOffset = CGPoint(x: pw * CGFloat(pager.currentPage), y: 0)
    }

    func scrollViewDidScroll(_ sv: UIScrollView) {
        guard sv.bounds.width > 0 else { return }
        pager.currentPage = Int((sv.contentOffset.x / sv.bounds.width).rounded())
    }

    @objc private func tapped(_ b: UIControl) {
        if let slot = Deck.shared[b.tag] {
            if Prefs.keyHaptics { feedback.impactOccurred() }
            slot.perform()
        } else {
            onEdit?(b.tag)
        }
    }

    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let b = g.view as? DeckButton else { return }
        b.cancelTracking(with: nil)
        b.isHighlighted = false
        onEdit?(b.tag)
    }
}
