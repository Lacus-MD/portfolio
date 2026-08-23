import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Amit a megosztólap mutat, amíg és miután dolgozunk.
struct ShareOutcome {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String?
    var isWorking: Bool

    static let working = ShareOutcome(
        symbol: "arrow.down.doc", tint: DS.Color.coral,
        title: "Átvétel…", detail: nil, isWorking: true
    )
    static func done(_ name: String) -> ShareOutcome {
        ShareOutcome(symbol: "checkmark.circle", tint: DS.Color.mint,
                     title: "Megkaptam",
                     detail: "\(name)\n\nA feldolgozás az app megnyitásakor történik — ahhoz árfolyamokat is le kell kérni.",
                     isWorking: false)
    }
    static func failed(_ message: String) -> ShareOutcome {
        ShareOutcome(symbol: "exclamationmark.triangle", tint: DS.Color.negativeCream,
                     title: "Nem sikerült", detail: message, isWorking: false)
    }
}

/// A megosztólap célpontja: átveszi a kivonatfájlt, és leteszi a közös
/// postaládába. A tényleges beolvasást az app végzi induláskor — a
/// kiterjesztés rövid életű, szűk memóriakeretű folyamat, és hálózatot
/// (devizatörténet!) nem érdemes benne futtatni.
final class ShareViewController: UIViewController {

    private var outcome: ShareOutcome = .working { didSet { render() } }
    private var host: UIHostingController<ShareStatusView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
        Task { await accept() }
    }

    private func render() {
        let view = ShareStatusView(outcome: outcome) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        if let host {
            host.rootView = view
        } else {
            let controller = UIHostingController(rootView: view)
            addChild(controller)
            controller.view.frame = self.view.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(controller.view)
            controller.didMove(toParent: self)
            host = controller
        }
    }

    private func accept() async {
        guard let item = (extensionContext?.inputItems as? [NSExtensionItem])?.first,
              let provider = item.attachments?.first else {
            outcome = .failed("Nem érkezett fájl.")
            return
        }
        do {
            let url = try await loadFileURL(from: provider)
            // A megosztott URL biztonsági hatókörű lehet — enélkül nem olvasható.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            // A FÁJLNEVET megőrizzük: a számlaazonosító abból derül ki.
            try Inbox.store(data, named: url.lastPathComponent)
            outcome = .done(url.lastPathComponent)
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async throws -> URL {
        // Ugyanaz a CSV több típusnév alatt is érkezhet, ezért sorban próbáljuk.
        for type in [UTType.commaSeparatedText, .plainText, .text, .data, .fileURL] {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }
            let loaded: URL? = try? await withCheckedThrowingContinuation { continuation in
                provider.loadItem(forTypeIdentifier: type.identifier) { item, error in
                    if let error { return continuation.resume(throwing: error) }
                    if let url = item as? URL { return continuation.resume(returning: url) }
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
            if let loaded { return loaded }
        }
        throw CocoaError(.fileReadUnsupportedScheme)
    }
}

private struct ShareStatusView: View {
    let outcome: ShareOutcome
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: outcome.symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(outcome.tint)
            Text(outcome.title).font(.headline)
            if let detail = outcome.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if !outcome.isWorking {
                Button("Kész", action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .tint(DS.Color.coral)
    }
}
