import UIKit

/// The modal progress card screens show over themselves while a long engine
/// call (import, sync) runs. It is added to the host's view — not presented —
/// so it cannot be swiped away and needs no presentation delegate plumbing.
///
/// Engine calls are one blocking RPC, so progress is phase text plus a
/// spinner rather than a percentage. The cancel button means "stop waiting":
/// the engine call cannot be interrupted safely, so the card stays up and
/// reports the outcome when the call returns. Screens wire `onCancel` and
/// decide what that means for their flow.
final class BlockingProgressView: UIView {
    private let card = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let cancelButton = AmgiButton(style: .secondary, title: "Cancel")

    /// Called when the user taps the cancel button; the overlay keeps
    /// running until the host updates it again.
    var onCancel: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)

        backgroundColor = UIColor.black.withAlphaComponent(0.35)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = AmgiColor.surface
        card.layer.cornerRadius = AmgiRadius.lg
        card.layer.cornerCurve = .continuous
        addSubview(card)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = AmgiTypography.headline
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = AmgiColor.textPrimary
        titleLabel.numberOfLines = 0

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = AmgiTypography.callout
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = AmgiColor.textSecondary
        statusLabel.numberOfLines = 0

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.accessibilityLabel = "Cancel"
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, spinner, statusLabel, cancelButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = AmgiSpacing.md
        card.addSubview(stack)

        // VoiceOver reads the card as one element; taps outside it are
        // swallowed by the dimmed background.
        isAccessibilityElement = true
        accessibilityLabel = title

        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor, constant: AmgiSpacing.xl
            ),
            card.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -AmgiSpacing.xl
            ),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: AmgiSpacing.lg),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -AmgiSpacing.lg),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AmgiSpacing.lg),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AmgiSpacing.lg),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var accessibilityLabel: String? {
        didSet { syncAccessibility() }
    }

    // MARK: - Updates from the host

    /// Starts the spinner again after a "stopped waiting" pause.
    func startAnimating() {
        spinner.startAnimating()
        syncAccessibility()
    }

    func stopAnimating() {
        spinner.stopAnimating()
        syncAccessibility()
    }

    func setStatus(_ text: String) {
        statusLabel.text = text
        syncAccessibility()
    }

    /// `nil` hides the cancel button entirely; a title re-labels it.
    func setCancelTitle(_ title: String?) {
        if let title {
            cancelButton.isHidden = false
            cancelButton.setTitle(title, for: .normal)
        } else {
            cancelButton.isHidden = true
        }
    }

    func setCancelEnabled(_ enabled: Bool) {
        cancelButton.isEnabled = enabled
    }

    // MARK: - Private

    @objc private func cancelTapped() {
        onCancel?()
    }

    /// Keeps the accessibility label in step with the visible text. The
    /// equality guard matters: `didSet` fires on every assignment, even when
    /// the value is unchanged, so an unconditional write would recurse.
    private func syncAccessibility() {
        var parts: [String] = [titleLabel.text ?? ""]
        parts.append(statusLabel.text ?? "")
        parts.append(spinner.isAnimating ? "Working" : "")
        let label = parts
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        if accessibilityLabel != label {
            accessibilityLabel = label
        }
    }
}

extension BlockingProgressView {
    /// Adds the overlay to a host view and pins it to the safe area.
    static func install(in hostView: UIView, title: String) -> BlockingProgressView {
        let overlay = BlockingProgressView(title: title)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: hostView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
        ])
        return overlay
    }
}
