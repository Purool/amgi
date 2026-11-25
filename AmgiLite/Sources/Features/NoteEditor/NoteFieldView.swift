import UIKit

/// One editable field: field name above, HTML source in an auto-growing text
/// view. Fields are edited as stored HTML (no WYSIWYG); the insertion bar adds
/// the handful of tags the editor expects to be common.
final class NoteFieldView: UIView {
    let index: Int

    var onTextChange: ((String) -> Void)?

    private let textView = UITextView()
    private var heightConstraint: NSLayoutConstraint!
    private let maxHeight: CGFloat = 320

    var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            updateHeight()
        }
    }

    init(index: Int, name: String, text: String) {
        self.index = index
        super.init(frame: .zero)

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = AmgiTypography.caption
        nameLabel.textColor = AmgiColor.textSecondary
        nameLabel.adjustsFontForContentSizeCategory = true

        textView.font = AmgiTypography.body
        textView.textColor = AmgiColor.textPrimary
        textView.backgroundColor = AmgiColor.surface
        textView.layer.cornerRadius = AmgiRadius.md
        textView.layer.cornerCurve = .continuous
        textView.textContainerInset = UIEdgeInsets(
            top: AmgiSpacing.sm,
            left: AmgiSpacing.sm,
            bottom: AmgiSpacing.sm,
            right: AmgiSpacing.sm
        )
        textView.text = text
        textView.delegate = self
        // HTML source: auto-substitutions corrupt markup.
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.spellCheckingType = .no
        textView.accessibilityLabel = name
        textView.inputAccessoryView = makeInsertionBar()

        let stack = UIStackView(arrangedSubviews: [nameLabel, textView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AmgiSpacing.xs
        addSubview(stack)

        heightConstraint = textView.heightAnchor.constraint(equalToConstant: 88)
        heightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightConstraint,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateHeight()
    }

    private func updateHeight() {
        guard textView.bounds.width > 0 else { return }
        let fitting = textView.sizeThatFits(
            CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        ).height
        let target = min(max(fitting, 88), maxHeight)
        if abs(heightConstraint.constant - target) > 0.5 {
            heightConstraint.constant = target
        }
        textView.isScrollEnabled = fitting > maxHeight
    }

    // MARK: - Insertion bar

    private func makeInsertionBar() -> UIView {
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 48))
        bar.autoresizingMask = [.flexibleWidth]
        bar.backgroundColor = AmgiColor.surfaceElevated

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        bar.addSubview(scroll)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = AmgiSpacing.sm
        scroll.addSubview(stack)

        let tokens: [(title: String, open: String, close: String, placeholder: String)] = [
            ("B", "<b>", "</b>", "bold"),
            ("I", "<i>", "</i>", "italic"),
            ("U", "<u>", "</u>", "underline"),
            ("<br>", "", "<br>", ""),
            ("{{c1::…}}", "{{c1::", "}}", "answer"),
        ]

        for token in tokens {
            let button = UIButton(type: .system)
            button.setTitle(token.title, for: .normal)
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
            button.addAction(UIAction { [weak self] _ in
                self?.insert(open: token.open, close: token.close, placeholder: token.placeholder)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: bar.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: AmgiSpacing.sm),
            scroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -AmgiSpacing.sm),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        return bar
    }

    private func insert(open: String, close: String, placeholder: String) {
        let range = textView.selectedRange
        guard let textRange = Range(range, in: textView.text) else { return }
        let selected = String(textView.text[textRange])

        let body = selected.isEmpty ? placeholder : selected
        let replacement = open + body + close
        textView.text.replaceSubrange(textRange, with: replacement)

        let bodyLength = (body as NSString).length
        let caret: Int
        if selected.isEmpty {
            caret = range.location + (open as NSString).length + bodyLength
        } else {
            caret = range.location + (replacement as NSString).length
        }
        textView.selectedRange = NSRange(location: caret, length: 0)
        textViewDidChange(textView)
    }
}

// MARK: - UITextViewDelegate

extension NoteFieldView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateHeight()
        onTextChange?(textView.text ?? "")
    }
}
