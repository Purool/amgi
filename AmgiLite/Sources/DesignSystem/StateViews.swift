import UIKit

/// Shared loading / empty / error surfaces. Every async screen has all three,
/// per `Sources/AGENTS.md`; keeping them here stops each screen from inventing
/// its own typography and spacing.
final class LoadingStateView: UIView {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    init(message: String = "Loading…") {
        super.init(frame: .zero)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = false

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.font = AmgiTypography.callout
        label.textColor = AmgiColor.textSecondary

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AmgiSpacing.sm
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: AmgiSpacing.lg),
        ])

        spinner.startAnimating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

final class EmptyStateView: UIView {
    private let action: (() -> Void)?

    init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.action = onAction
        super.init(frame: .zero)

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = AmgiColor.textTertiary
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false

        let titleLabel = UILabel()
        titleLabel.font = AmgiTypography.headline
        titleLabel.textColor = AmgiColor.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = title

        let messageLabel = UILabel()
        messageLabel.font = AmgiTypography.callout
        messageLabel.textColor = AmgiColor.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.text = message

        var arranged: [UIView] = [icon, titleLabel, messageLabel]
        if let actionTitle {
            let button = AmgiButton(style: .primary, title: actionTitle)
            button.addTarget(self, action: #selector(runAction), for: .touchUpInside)
            arranged.append(button)
        }

        let stack = UIStackView(arrangedSubviews: arranged)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AmgiSpacing.sm
        stack.setCustomSpacing(AmgiSpacing.md, after: icon)
        addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: AmgiSpacing.lg),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -AmgiSpacing.lg),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func runAction() {
        action?()
    }
}

final class ErrorStateView: UIView {
    private let retry: () -> Void

    init(message: String, retry: @escaping () -> Void) {
        self.retry = retry
        super.init(frame: .zero)

        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = AmgiColor.danger
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false

        let label = UILabel()
        label.font = AmgiTypography.callout
        label.textColor = AmgiColor.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = message

        let button = AmgiButton(style: .secondary, title: "Try Again")
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, label, button])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AmgiSpacing.md
        addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: AmgiSpacing.lg),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -AmgiSpacing.lg),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func retryTapped() {
        retry()
    }
}
