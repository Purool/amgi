import AnkiKit
import UIKit

/// Full-screen FSRS weight editor: the comma-separated parameter list, plus
/// "Optimize Weights". Optimizing only fills the text — it never saves; the
/// parent screen writes `fsrsParams6` when the user presses Save there.
@MainActor
final class FsrsWeightsViewController: UIViewController {
    private let initialText: String
    private let paramSearch: String
    private let relearningSteps: UInt32
    private let runHealthCheck: Bool
    private let services: LiteServices

    private let textView = UITextView()
    private let statusLabel = UILabel()
    private let optimizeButton = AmgiButton(style: .primary, title: "Optimize Weights")
    private var progressView: BlockingProgressView?
    private var keyboardAvoider: KeyboardAvoider?

    /// Called when the user leaves with Done. The parent marks the weights as
    /// edited, which is what enables writing `fsrsParams6` on save.
    var onApply: ((String) -> Void)?

    init(
        initialText: String,
        paramSearch: String,
        relearningSteps: UInt32,
        runHealthCheck: Bool,
        services: LiteServices
    ) {
        self.initialText = initialText
        self.paramSearch = paramSearch
        self.relearningSteps = relearningSteps
        self.runHealthCheck = runHealthCheck
        self.services = services
        super.init(nibName: nil, bundle: nil)
        title = "FSRS Weights"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        setUpLayout()
        keyboardAvoider = KeyboardAvoider(rootView: view, scrollView: textView)
    }

    private func setUpLayout() {
        let explanation = UILabel()
        explanation.font = AmgiTypography.caption
        explanation.textColor = AmgiColor.textSecondary
        explanation.adjustsFontForContentSizeCategory = true
        explanation.numberOfLines = 0
        explanation.text = """
        One FSRS parameter per value, separated by commas or spaces. Optimizing \
        fills new values but does not save them — press Done, then Save on the \
        options screen.
        """

        textView.font = AmgiTypography.mono
        textView.textColor = AmgiColor.textPrimary
        textView.backgroundColor = AmgiColor.surface
        textView.layer.cornerRadius = AmgiRadius.md
        textView.layer.cornerCurve = .continuous
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(
            top: AmgiSpacing.md,
            left: AmgiSpacing.md,
            bottom: AmgiSpacing.md,
            right: AmgiSpacing.md
        )
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.text = initialText
        textView.accessibilityLabel = "FSRS weights"

        statusLabel.font = AmgiTypography.callout
        statusLabel.textColor = AmgiColor.textSecondary
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.text = initialText.isEmpty
            ? "This preset has no weights yet."
            : nil

        optimizeButton.addTarget(self, action: #selector(optimizeTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            explanation, textView, statusLabel, optimizeButton,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AmgiSpacing.md
        view.addSubview(stack)

        textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: AmgiSpacing.md
            ),
            stack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AmgiSpacing.md
            ),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AmgiSpacing.md),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AmgiSpacing.md),
        ])
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        textView.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Done and the back button both hand the text to the parent draft;
        // persisting still requires Save on the deck-options screen.
        if isMovingFromParent || isBeingDismissed {
            onApply?(textView.text)
        }
    }

    @objc private func optimizeTapped() {
        guard progressView == nil else { return }

        let currentWeights = parseDeckFloats(textView.text)
        let overlay = BlockingProgressView.install(in: view, title: "Optimizing FSRS weights")
        overlay.setStatus("Training on the review history. This can take a while.")
        overlay.setCancelTitle("Stop waiting")
        overlay.onCancel = { [weak self] in
            // E10: no interrupt RPC — cancel only stops waiting.
            overlay.stopAnimating()
            overlay.setStatus("Stopped waiting — optimization continues in the engine.")
            overlay.setCancelTitle(nil)
        }
        progressView = overlay

        Task { [weak self] in
            guard let self else { return }
            let request = FsrsOptimizeRequest(
                search: self.paramSearch,
                currentWeights: FsrsWeights(currentWeights),
                relearningStepsPerDay: Int(self.relearningSteps),
                runHealthCheck: self.runHealthCheck
            )
            do {
                let result = try await self.services.deckOptions.optimizeWeights(request)
                self.finishOptimize(result)
            } catch {
                self.dismissProgress()
                Alerts.present(error: error, title: "Couldn't optimize weights", on: self)
            }
        }
    }

    private func finishOptimize(_ result: FsrsOptimizeResult) {
        dismissProgress()

        // E11: zero training items is "not enough history", not an empty result.
        guard result.trainingItemCount > 0, !result.weights.isEmpty else {
            statusLabel.text = "Not enough review history to optimize yet."
            Alerts.presentMessage(
                title: "Not enough review history",
                message: "FSRS needs more reviews before it can train. The existing weights were left unchanged.",
                on: self
            )
            return
        }

        textView.text = formatDeckWeights(result.weights.values)
        statusLabel.text = "Optimized from \(result.trainingItemCount) reviews. Press Done, then Save."

        if result.healthCheck == .failed {
            Alerts.presentMessage(
                title: "Health check failed",
                message: "The review history looks inconsistent. Review the new parameters before saving.",
                on: self
            )
        }
    }

    private func dismissProgress() {
        progressView?.removeFromSuperview()
        progressView = nil
    }
}
