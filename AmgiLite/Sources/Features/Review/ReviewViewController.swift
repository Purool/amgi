import AnkiKit
import UIKit

/// The review screen: a card surface, front/back flow, four grading keys,
/// progress caption and undo. State comes from `ReviewViewModel` through
/// `onStateChange`; only the transient-error callback surfaces as an alert so
/// a failed answer or undo never kicks the user off the card.
@MainActor
final class ReviewViewController: UIViewController {
    private let viewModel: ReviewViewModel
    private let cardSurface: CardWebView

    private let progressLabel = UILabel()
    private let frontButton = AmgiButton(style: .primary, title: "Show Answer")
    private let doneButton = AmgiButton(style: .primary, title: "Done")
    private let ratingStack = UIStackView(arrangedSubviews: [])
    private let loadingView = LoadingStateView(message: "Rendering…")
    private var errorView: ErrorStateView?
    private var doneView: UIView?
    private var undoItem: UIBarButtonItem?

    /// The card face currently loaded, kept for dark-mode re-renders.
    private var lastReady: ReviewViewModel.ReadyCard?
    private var lastSide: CardSide = .front

    init(services: LiteServices, session: CollectionSession, deckID: DeckID) {
        self.viewModel = ReviewViewModel(services: services, session: session, deckID: deckID)

        let collection = services.collection
        // Strong capture on purpose: `CollectionServicing` is not class-bound,
        // so it cannot be captured weakly (the temporary Phase 1 preview did
        // the same). The backend behind it is owned by `AppContainer` anyway.
        self.cardSurface = CardWebView(mediaRootProvider: {
            collection.mediaFolderPath.map { URL(fileURLWithPath: $0) }
        })

        super.init(nibName: nil, bundle: nil)
        title = "Review"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        setUpLayout()
        setUpNavigationItem()

        viewModel.onStateChange = { [weak self] state in
            self?.apply(state)
        }
        viewModel.onTransientError = { [weak self] message in
            self?.presentTransientError(message)
        }

        viewModel.start()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // The page bakes its colors in; dark-mode switches need a fresh render
        // of whichever side is on screen.
        guard
            traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
            let lastReady
        else { return }
        render(lastReady, side: lastSide)
    }

    // MARK: - Layout

    private func setUpLayout() {
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.font = AmgiTypography.callout
        progressLabel.textColor = AmgiColor.textSecondary
        progressLabel.textAlignment = .center
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.text = "Answered 0 · Remaining 0"

        cardSurface.translatesAutoresizingMaskIntoConstraints = false
        cardSurface.isHidden = true

        ratingStack.translatesAutoresizingMaskIntoConstraints = false
        ratingStack.axis = .horizontal
        ratingStack.distribution = .fillEqually
        ratingStack.spacing = AmgiSpacing.xs

        frontButton.translatesAutoresizingMaskIntoConstraints = false
        frontButton.addTarget(self, action: #selector(showAnswerTapped), for: .touchUpInside)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        let controlsStack = UIStackView(arrangedSubviews: [frontButton, ratingStack])
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.axis = .vertical
        controlsStack.alignment = .fill
        controlsStack.spacing = AmgiSpacing.md
        frontButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [progressLabel, cardSurface, controlsStack])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AmgiSpacing.md
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AmgiSpacing.md),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AmgiSpacing.md),
        ])

        // Full-screen overlay for the loading state, added after the stack so
        // it sits above it in z-order. Error and done overlays are built on
        // demand in `showErrorOverlay` / `showDoneOverlay`.
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingView)
        NSLayoutConstraint.activate([
            loadingView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            loadingView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setUpNavigationItem() {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain,
            target: self,
            action: #selector(undoTapped)
        )
        item.accessibilityLabel = "Undo"
        item.isEnabled = false
        navigationItem.rightBarButtonItem = item
        undoItem = item
    }

    // MARK: - State application

    private func apply(_ state: ReviewViewModel.State) {
        loadingView.isHidden = true
        errorView?.isHidden = true
        doneView?.isHidden = true
        cardSurface.isHidden = true

        switch state {
        case .loading:
            loadingView.isHidden = false
            showControls(front: false, ratings: false)
        case .front(let ready):
            lastReady = ready
            lastSide = .front
            cardSurface.isHidden = false
            render(ready, side: .front)
            showControls(front: true, ratings: false)
        case .back(let ready, let specs):
            lastReady = ready
            lastSide = .back
            cardSurface.isHidden = false
            render(ready, side: .back)
            configureRatingButtons(with: specs)
            showControls(front: false, ratings: true)
        case .done(let count):
            showDoneOverlay(answered: count)
            showControls(front: false, ratings: false)
        case .error(let message):
            showErrorOverlay(message: message)
            showControls(front: false, ratings: false)
        }

        progressLabel.text = "Answered \(viewModel.answeredCount) · Remaining \(viewModel.remainingCount)"
        undoItem?.isEnabled = viewModel.answeredCount > 0
    }

    private func showControls(front: Bool, ratings: Bool) {
        frontButton.isHidden = !front
        ratingStack.isHidden = !ratings
    }

    private func render(_ ready: ReviewViewModel.ReadyCard, side: CardSide) {
        let page = CardPageBuilder.page(
            for: ready.rendered,
            side: side,
            isDark: traitCollection.userInterfaceStyle == .dark
        )
        cardSurface.load(html: page, baseURL: nil)
    }

    private func configureRatingButtons(with specs: [ReviewViewModel.RatingButtonSpec]) {
        ratingStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for spec in specs {
            let kind: RatingButtonView.Kind
            switch spec.rating {
            case .again: kind = .again
            case .hard: kind = .hard
            case .good: kind = .good
            case .easy: kind = .easy
            }
            let button = RatingButtonView(kind: kind)
            button.intervalText = spec.interval
            button.tag = Int(spec.rating.rawValue)
            button.addTarget(self, action: #selector(ratingTapped(_:)), for: .touchUpInside)
            ratingStack.addArrangedSubview(button)
        }
    }

    private func showErrorOverlay(message: String) {
        errorView?.removeFromSuperview()
        let replacement = ErrorStateView(message: message, retry: { [weak self] in
            self?.viewModel.retry()
        })
        pinOverlay(replacement)
        errorView = replacement
    }

    private func showDoneOverlay(answered: Int) {
        doneView?.removeFromSuperview()
        let empty = EmptyStateView(
            symbol: "checkmark.circle",
            title: "All done",
            message: "Answered \(answered) cards. Nothing left in the queue."
        )
        let stack = UIStackView(arrangedSubviews: [empty, doneButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AmgiSpacing.md
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -AmgiSpacing.md),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AmgiSpacing.md),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AmgiSpacing.md),
        ])
        doneView = stack
    }

    private func pinOverlay(_ overlay: UIView) {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func presentTransientError(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Engine error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func showAnswerTapped() {
        viewModel.showAnswer()
    }

    @objc private func ratingTapped(_ sender: RatingButtonView) {
        guard let rating = Rating(rawValue: Int16(sender.tag)) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.rate(rating)
    }

    @objc private func undoTapped() {
        viewModel.undo()
    }

    @objc private func doneTapped() {
        navigationController?.popViewController(animated: true)
    }
}
