import AnkiKit
import UIKit

/// Read-only note detail (S8): the sort field as title, tags, then every field
/// in order. v1 is deliberately read-only — editing is out of scope for the
/// basic build; no editing entry point is offered on this screen.
@MainActor
final class NoteDetailViewController: UIViewController {
    private enum Phase {
        case loading
        case content(NoteRecord)
        case error(String)
    }

    private let services: LiteServices
    private let noteID: NoteID

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let loadingView = LoadingStateView(message: "Loading note…")
    private var errorView: ErrorStateView?

    private var phase: Phase = .loading {
        didSet { render(phase) }
    }

    init(services: LiteServices, noteID: NoteID) {
        self.services = services
        self.noteID = noteID
        super.init(nibName: nil, bundle: nil)
        title = "Note"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        setUpScrollView()
        setUpLoadingView()

        fetch()
    }

    // MARK: Setup

    private func setUpScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AmgiSpacing.md
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: AmgiSpacing.lg),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -AmgiSpacing.lg),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: AmgiSpacing.lg),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -AmgiSpacing.lg),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * AmgiSpacing.lg),
        ])
    }

    private func setUpLoadingView() {
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingView)
        NSLayoutConstraint.activate([
            loadingView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            loadingView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: Fetch

    private func fetch() {
        phase = .loading
        let noteID = self.noteID
        Task { [weak self] in
            guard let self else { return }
            do {
                let note = try await self.services.browse.note(id: noteID)
                // The browse screen keeps the collection open, so a fresh push
                // reads straight through; a stale fetch after close lands in
                // the error state with retry.
                self.phase = .content(note)
            } catch {
                self.phase = .error("Engine error: \(error)")
            }
        }
    }

    // MARK: Phases

    private func render(_ phase: Phase) {
        switch phase {
        case .loading:
            errorView?.removeFromSuperview()
            errorView = nil
            scrollView.isHidden = true
            loadingView.isHidden = false

        case .content(let note):
            errorView?.removeFromSuperview()
            errorView = nil
            loadingView.isHidden = true
            scrollView.isHidden = false
            renderContent(note)

        case .error(let message):
            errorView?.removeFromSuperview()
            loadingView.isHidden = true
            scrollView.isHidden = true

            let replacement = ErrorStateView(message: message, retry: { [weak self] in
                self?.fetch()
            })
            replacement.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(replacement)
            NSLayoutConstraint.activate([
                replacement.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                replacement.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                replacement.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                replacement.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            errorView = replacement
        }
    }

    private func renderContent(_ note: NoteRecord) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        stack.addArrangedSubview(titleLabel(of: note))

        let tags = note.tags.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tags.isEmpty {
            let tagsLabel = UILabel()
            tagsLabel.text = "Tags: \(tags)"
            tagsLabel.font = AmgiTypography.caption
            tagsLabel.textColor = AmgiColor.textTertiary
            tagsLabel.numberOfLines = 0
            tagsLabel.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(tagsLabel)
        }

        let fields = note.flds
            .split(separator: "\u{1F}", omittingEmptySubsequences: false)
            .map(String.init)

        for (index, field) in fields.enumerated() {
            let heading = UILabel()
            heading.text = "Field \(index + 1)"
            heading.font = AmgiTypography.caption
            heading.textColor = AmgiColor.textTertiary
            heading.adjustsFontForContentSizeCategory = true

            let value = NoteSummary.plainText(field)
            let valueLabel = UILabel()
            valueLabel.text = value.isEmpty ? "(empty)" : value
            valueLabel.font = AmgiTypography.body
            valueLabel.textColor = AmgiColor.textPrimary
            valueLabel.numberOfLines = 0
            valueLabel.adjustsFontForContentSizeCategory = true

            stack.addArrangedSubview(heading)
            stack.addArrangedSubview(valueLabel)
        }
    }

    private func titleLabel(of note: NoteRecord) -> UILabel {
        let label = UILabel()
        label.text = NoteSummary.plainText(note.sfld)
        label.font = AmgiTypography.title
        label.textColor = AmgiColor.textPrimary
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        // Plain labels are VoiceOver-readable as-is; no custom element needed.
        return label
    }
}
