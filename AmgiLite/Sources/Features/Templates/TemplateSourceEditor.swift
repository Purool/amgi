import UIKit

/// Source editor for one template panel. Smart quotes and autocorrection are
/// off on purpose: replacing a quote inside HTML/CSS is a real bug, not a
/// convenience. The accessory bar inserts `{{Field}}` tokens at the cursor or
/// over the selected range.
final class TemplateSourceEditor: UITextView {
    var onTextChange: ((String) -> Void)?

    private let accessoryStack = UIStackView()
    private var tokens: [String] = []

    init() {
        super.init(frame: .zero, textContainer: nil)

        font = AmgiTypography.mono
        textColor = AmgiColor.textPrimary
        backgroundColor = AmgiColor.surface
        layer.cornerRadius = AmgiRadius.md
        layer.cornerCurve = .continuous
        textContainerInset = UIEdgeInsets(
            top: AmgiSpacing.md,
            left: AmgiSpacing.md,
            bottom: AmgiSpacing.md,
            right: AmgiSpacing.md
        )
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        spellCheckingType = .no
        keyboardType = .asciiCapable
        isScrollEnabled = true
        alwaysBounceVertical = true
        accessibilityLabel = "Template source"

        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 48))
        bar.autoresizingMask = [.flexibleWidth]
        bar.backgroundColor = AmgiColor.surfaceElevated

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        bar.addSubview(scroll)

        accessoryStack.translatesAutoresizingMaskIntoConstraints = false
        accessoryStack.axis = .horizontal
        accessoryStack.alignment = .center
        accessoryStack.spacing = AmgiSpacing.sm
        scroll.addSubview(accessoryStack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: bar.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: AmgiSpacing.sm),
            scroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -AmgiSpacing.sm),

            accessoryStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            accessoryStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            accessoryStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            accessoryStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            accessoryStack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        inputAccessoryView = bar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Rebuilds the insertion bar. Called whenever the selected template
    /// changes (fields are per notetype, not per template).
    func setFieldTokens(_ tokens: [String]) {
        self.tokens = tokens
        accessoryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, token) in tokens.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.setTitle(token, for: .normal)
            button.titleLabel?.font = AmgiTypography.mono
            button.setTitleColor(AmgiColor.accent, for: .normal)
            button.backgroundColor = AmgiColor.surface
            button.layer.cornerRadius = AmgiRadius.sm
            button.contentEdgeInsets = UIEdgeInsets(
                top: AmgiSpacing.xs,
                left: AmgiSpacing.sm,
                bottom: AmgiSpacing.xs,
                right: AmgiSpacing.sm
            )
            button.addTarget(self, action: #selector(tokenTapped(_:)), for: .touchUpInside)
            accessoryStack.addArrangedSubview(button)
        }
    }

    /// Replaces the current selection with `token` and keeps the caret after
    /// the insertion.
    func insert(_ token: String) {
        let range = selectedRange
        guard let textRange = Range(range, in: text) else { return }
        text.replaceSubrange(textRange, with: token)
        selectedRange = NSRange(
            location: range.location + (token as NSString).length,
            length: 0
        )
        onTextChange?(text)
    }

    @objc private func tokenTapped(_ sender: UIButton) {
        guard tokens.indices.contains(sender.tag) else { return }
        insert(tokens[sender.tag])
    }
}
