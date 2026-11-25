import UIKit

// Form rows for iOS 14. SwiftUI's `Form` and `UIButton.Configuration` do not
// exist here, so every "title + secondary + trailing control" row is a
// `UICollectionViewListCell` subclass with the control as a custom accessory.
// Screens use these instead of building their own rows.

/// One section header/footer. Registered as a supplementary view by screens
/// that set `headerMode = .supplementary`.
final class AmgiSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "AmgiSectionHeaderView"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AmgiTypography.caption
        label.textColor = AmgiColor.textSecondary
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: AmgiSpacing.sm),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AmgiSpacing.xs),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AmgiSpacing.md + AmgiSpacing.xs),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AmgiSpacing.md),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(text: String) {
        label.text = text.uppercased()
    }
}

/// Base for rows whose trailing control lives in a custom accessory. Central
/// place for the title/secondary content configuration so every row reads the
/// same.
class AmgiFormRowCell: UICollectionViewListCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = UIBackgroundConfiguration.clear()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func applyTitle(_ title: String, secondary: String? = nil, enabled: Bool = true) {
        var content = defaultContentConfiguration()
        content.text = title
        content.textProperties.font = AmgiTypography.body
        content.textProperties.color = enabled ? AmgiColor.textPrimary : AmgiColor.textTertiary
        content.textProperties.adjustsFontForContentSizeCategory = true
        if let secondary {
            content.secondaryText = secondary
            content.secondaryTextProperties.font = AmgiTypography.caption
            content.secondaryTextProperties.color = AmgiColor.textSecondary
            content.secondaryTextProperties.numberOfLines = 0
            content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        }
        contentConfiguration = content
    }
}

// MARK: - Switch

final class AmgiSwitchRowCell: AmgiFormRowCell {
    private let toggle = UISwitch()
    private var onChange: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        accessories = [
            .customView(configuration: .init(
                customView: toggle,
                placement: .trailing(displayed: .always)
            )),
        ]
    }

    func configure(
        title: String,
        secondary: String? = nil,
        isOn: Bool,
        enabled: Bool = true,
        accessibilityLabel: String? = nil,
        onChange: @escaping (Bool) -> Void
    ) {
        applyTitle(title, secondary: secondary, enabled: enabled)
        toggle.isOn = isOn
        toggle.isEnabled = enabled
        toggle.accessibilityLabel = accessibilityLabel ?? title
        toggle.accessibilityValue = isOn ? "On" : "Off"
        self.onChange = onChange
    }

    @objc private func toggleChanged() {
        toggle.accessibilityValue = toggle.isOn ? "On" : "Off"
        onChange?(toggle.isOn)
    }
}

// MARK: - Stepper

final class AmgiStepperRowCell: AmgiFormRowCell {
    private let titleLabel = UILabel()
    private let secondaryLabel = UILabel()
    private let valueLabel = UILabel()
    private let stepper = UIStepper()
    private var onChange: ((Double) -> Void)?
    private var display: ((Double) -> String)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = AmgiTypography.body
        titleLabel.textColor = AmgiColor.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        secondaryLabel.font = AmgiTypography.caption
        secondaryLabel.textColor = AmgiColor.textSecondary
        secondaryLabel.adjustsFontForContentSizeCategory = true
        secondaryLabel.numberOfLines = 0
        secondaryLabel.isHidden = true

        valueLabel.font = AmgiTypography.body
        valueLabel.textColor = AmgiColor.textSecondary
        valueLabel.textAlignment = .right
        valueLabel.adjustsFontForContentSizeCategory = true

        stepper.addTarget(self, action: #selector(stepperChanged), for: .valueChanged)
        stepper.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, secondaryLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [textStack, valueLabel, stepper])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = AmgiSpacing.sm
        contentView.addSubview(row)

        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AmgiSpacing.sm + 2,
            leading: AmgiSpacing.md + AmgiSpacing.xs,
            bottom: AmgiSpacing.sm + 2,
            trailing: AmgiSpacing.md
        )
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    func configure(
        title: String,
        secondary: String? = nil,
        value: Double,
        range: ClosedRange<Double>,
        step: Double = 1,
        display: @escaping (Double) -> String,
        accessibleValue: String? = nil,
        onChange: @escaping (Double) -> Void
    ) {
        titleLabel.text = title
        secondaryLabel.text = secondary
        secondaryLabel.isHidden = secondary == nil
        self.onChange = onChange

        valueLabel.text = display(value)
        self.display = display
        stepper.minimumValue = range.lowerBound
        stepper.maximumValue = range.upperBound
        stepper.stepValue = step
        stepper.value = min(max(value, range.lowerBound), range.upperBound)
        stepper.accessibilityLabel = title
        stepper.accessibilityValue = accessibleValue ?? display(value)
    }

    @objc private func stepperChanged() {
        let text = display?(stepper.value) ?? "\(Int(stepper.value))"
        valueLabel.text = text
        stepper.accessibilityValue = text
        onChange?(stepper.value)
    }
}

// MARK: - Text field

final class AmgiTextRowCell: AmgiFormRowCell, UITextFieldDelegate {
    private let titleLabel = UILabel()
    private let secondaryLabel = UILabel()
    private let textField = UITextField()
    private var onCommit: ((String) -> Void)?
    private var onChange: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = AmgiTypography.body
        titleLabel.textColor = AmgiColor.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        secondaryLabel.font = AmgiTypography.caption
        secondaryLabel.textColor = AmgiColor.textSecondary
        secondaryLabel.adjustsFontForContentSizeCategory = true
        secondaryLabel.numberOfLines = 0
        secondaryLabel.isHidden = true

        textField.font = AmgiTypography.body
        textField.textColor = AmgiColor.textPrimary
        textField.textAlignment = .right
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.adjustsFontForContentSizeCategory = true
        textField.delegate = self
        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        textField.setContentCompressionResistancePriority(.required, for: .horizontal)
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, secondaryLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [textStack, textField])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = AmgiSpacing.sm
        contentView.addSubview(row)

        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AmgiSpacing.sm + 2,
            leading: AmgiSpacing.md + AmgiSpacing.xs,
            bottom: AmgiSpacing.sm + 2,
            trailing: AmgiSpacing.md
        )
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    func configure(
        title: String,
        secondary: String? = nil,
        text: String,
        placeholder: String? = nil,
        keyboardType: UIKeyboardType = .default,
        onChange: ((String) -> Void)? = nil,
        onCommit: @escaping (String) -> Void
    ) {
        titleLabel.text = title
        secondaryLabel.text = secondary
        secondaryLabel.isHidden = secondary == nil
        textField.text = text
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.accessibilityLabel = title
        self.onChange = onChange
        self.onCommit = onCommit
    }

    var isEditingText: Bool { textField.isFirstResponder }

    func commitPendingText() {
        onCommit?(textField.text ?? "")
    }

    @objc private func editingChanged() {
        textField.accessibilityValue = textField.text
        onChange?(textField.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        onCommit?(textField.text ?? "")
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        onCommit?(textField.text ?? "")
    }
}

// MARK: - Menu

struct AmgiMenuOption {
    let title: String
    let isSelected: Bool

    init(title: String, isSelected: Bool = false) {
        self.title = title
        self.isSelected = isSelected
    }
}

final class AmgiMenuRowCell: AmgiFormRowCell {
    private let titleLabel = UILabel()
    private let button = UIButton(type: .system)
    private var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = AmgiTypography.body
        titleLabel.textColor = AmgiColor.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        button.titleLabel?.font = AmgiTypography.body
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.setTitleColor(AmgiColor.accent, for: .normal)
        button.contentHorizontalAlignment = .right
        button.showsMenuAsPrimaryAction = true
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [titleLabel, button])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = AmgiSpacing.sm
        contentView.addSubview(row)

        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AmgiSpacing.sm + 2,
            leading: AmgiSpacing.md + AmgiSpacing.xs,
            bottom: AmgiSpacing.sm + 2,
            trailing: AmgiSpacing.md
        )
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    func configure(
        title: String,
        options: [AmgiMenuOption],
        accessibilityValue: String? = nil,
        enabled: Bool = true,
        onSelect: @escaping (Int) -> Void
    ) {
        titleLabel.text = title
        titleLabel.textColor = enabled ? AmgiColor.textPrimary : AmgiColor.textTertiary
        self.onSelect = onSelect
        button.isEnabled = enabled
        button.accessibilityLabel = title
        button.accessibilityValue = accessibilityValue ?? options.first(where: \.isSelected)?.title

        let selectedTitle = options.first(where: \.isSelected)?.title ?? "—"
        button.setTitle(selectedTitle, for: .normal)

        button.menu = UIMenu(children: options.enumerated().map { index, option in
            UIAction(
                title: option.title,
                state: option.isSelected ? .on : .off
            ) { [weak self] _ in
                self?.onSelect?(index)
            }
        })
    }
}

// MARK: - Disclosure / value

final class AmgiDisclosureRowCell: AmgiFormRowCell {
    func configure(title: String, secondary: String? = nil, detail: String? = nil) {
        applyTitle(title, secondary: secondary)
        if let detail {
            accessories = [.label(text: detail)]
        } else {
            accessories = [.disclosureIndicator()]
        }
    }
}

// MARK: - Slider

final class AmgiSliderRowCell: AmgiFormRowCell {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private var onChange: ((Float) -> Void)?
    private var display: (Float) -> String = { "\($0)" }

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = AmgiTypography.body
        titleLabel.textColor = AmgiColor.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true

        valueLabel.font = AmgiTypography.body
        valueLabel.textColor = AmgiColor.textSecondary
        valueLabel.textAlignment = .right
        valueLabel.adjustsFontForContentSizeCategory = true

        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.accessibilityLabel = nil

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        titleRow.axis = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = AmgiSpacing.sm

        let stack = UIStackView(arrangedSubviews: [titleRow, slider])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AmgiSpacing.xs
        contentView.addSubview(stack)

        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AmgiSpacing.sm,
            leading: AmgiSpacing.md + AmgiSpacing.xs,
            bottom: AmgiSpacing.sm,
            trailing: AmgiSpacing.md
        )

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    func configure(
        title: String,
        value: Float,
        range: ClosedRange<Float>,
        display: @escaping (Float) -> String,
        enabled: Bool = true,
        onChange: @escaping (Float) -> Void
    ) {
        titleLabel.text = title
        titleLabel.textColor = enabled ? AmgiColor.textPrimary : AmgiColor.textTertiary
        valueLabel.text = display(value)
        slider.minimumValue = range.lowerBound
        slider.maximumValue = range.upperBound
        slider.value = min(max(value, range.lowerBound), range.upperBound)
        slider.isEnabled = enabled
        slider.accessibilityLabel = title
        slider.accessibilityValue = display(value)
        self.display = display
        self.onChange = onChange
    }

    @objc private func sliderChanged() {
        valueLabel.text = display(slider.value)
        slider.accessibilityValue = valueLabel.text
        onChange?(slider.value)
    }
}

// MARK: - Action row

final class AmgiActionRowCell: AmgiFormRowCell {
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)

        spinner.hidesWhenStopped = true
        accessories = [
            .customView(configuration: .init(
                customView: spinner,
                placement: .trailing(displayed: .always)
            )),
        ]
    }

    func configure(title: String, busy: Bool = false, enabled: Bool = true) {
        var content = defaultContentConfiguration()
        content.text = title
        content.textProperties.font = AmgiTypography.body
        content.textProperties.color = enabled ? AmgiColor.accent : AmgiColor.textTertiary
        content.textProperties.adjustsFontForContentSizeCategory = true
        contentConfiguration = content

        if busy {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        accessibilityTraits = enabled ? .button : [.button, .notEnabled]
        isUserInteractionEnabled = enabled
    }
}

// MARK: - Info row

final class AmgiInfoRowCell: AmgiFormRowCell {
    func configure(
        title: String? = nil,
        message: String,
        tone: Tone = .secondary
    ) {
        var content = defaultContentConfiguration()
        content.text = title
        content.textProperties.font = AmgiTypography.caption
        content.textProperties.color = AmgiColor.textSecondary
        content.textProperties.adjustsFontForContentSizeCategory = true

        if title != nil {
            content.secondaryText = message
        } else {
            content.text = message
            content.textProperties.font = AmgiTypography.callout
        }
        let color: UIColor
        switch tone {
        case .secondary: color = AmgiColor.textSecondary
        case .warning: color = AmgiColor.warning
        case .danger: color = AmgiColor.danger
        }
        content.textProperties.color = color
        if title != nil {
            content.secondaryTextProperties.font = AmgiTypography.callout
            content.secondaryTextProperties.color = color
            content.secondaryTextProperties.numberOfLines = 0
            content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        } else {
            content.textProperties.numberOfLines = 0
        }
        contentConfiguration = content
    }

    enum Tone {
        case secondary
        case warning
        case danger
    }
}
