import OSLog
import SwiftUI
import UIKit

/// Shows iOS's share sheet for a prepared file (JUN-8). Not `ShareLink`: the file is prepared first, on the
/// card, so an iCloud download never stalls inside Messages. Sits in the deck's background and presents
/// `UIActivityViewController` once per payload from the window's root; `onFinish` runs when the sheet
/// closes, sent or not, so the file can be removed.
///
/// The file can arrive after the user opened a viewer or a sheet, or left the Feed tab. The sheet isn't
/// put over those: `onCouldNotPresent` runs instead, so a payload is never left waiting and later shares
/// aren't blocked.
///
/// The sheet itself is never taken for something in the way. SwiftUI can rebuild this view (and its
/// coordinator) while the sheet is up, and the new one sees the payload as unshown; before, it found its
/// own sheet "in the way" and reported a refusal, which deleted the file under the open sheet, so Copy,
/// Messages and AirDrop got nothing. Each sheet carries its payload's id, and a coordinator that finds the
/// sheet for its payload already up adopts it instead.
struct ShareSheetPresenter: UIViewControllerRepresentable {
    let payload: SharePayload?
    let onFinish: () -> Void
    let onCouldNotPresent: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.isUserInteractionEnabled = false
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.onFinish = onFinish
        coordinator.onCouldNotPresent = onCouldNotPresent
        guard let payload, coordinator.presentedID != payload.id else { return }
        coordinator.presentedID = payload.id
        // After this update, so the host is in the window.
        DispatchQueue.main.async { coordinator.present(payload, from: host) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The share sheet, tagged with the payload it shows.
    final class SheetController: UIActivityViewController {
        var payloadID: SharePayload.ID?
    }

    @MainActor
    final class Coordinator {
        var presentedID: SharePayload.ID?
        var onFinish: () -> Void = {}
        var onCouldNotPresent: () -> Void = {}
        private var finishedID: SharePayload.ID?
        private let log = Logger.app(category: "share")

        func present(_ payload: SharePayload, from host: UIViewController) {
            guard let root = host.view.window?.rootViewController else {
                log.error("Share sheet not shown: the deck isn't in a window")
                return finish(payload.id, presented: false)
            }
            // Already up for this payload (presented by an earlier coordinator): take over its completion.
            if let sheet = Self.presentedChain(from: root).compactMap({ $0 as? SheetController }).first(where: { $0.payloadID == payload.id }) {
                log.info("Share sheet already up; adopting it")
                attach(sheet, to: payload.id)
                return
            }
            // UIKit refuses a presentation silently (the completion handler then never runs) when the root is
            // already presenting or mid-transition, so those are checked here. Nothing is checked after
            // `present`: the share sheet loads its targets before it attaches, so an early look sees it
            // unpresented.
            guard root.presentedViewController == nil, !root.isBeingPresented, !root.isBeingDismissed else {
                let blocker = root.presentedViewController.map { String(describing: type(of: $0)) } ?? "a transition"
                log.error("Share sheet not shown: \(blocker, privacy: .public) is up")
                return finish(payload.id, presented: false)
            }
            let sheet = SheetController(activityItems: [payload.url], applicationActivities: nil)
            sheet.payloadID = payload.id
            sheet.popoverPresentationController?.sourceView = host.view
            attach(sheet, to: payload.id)
            root.present(sheet, animated: true)
        }

        private func attach(_ sheet: SheetController, to id: SharePayload.ID) {
            // Strong: an old coordinator SwiftUI dropped must still remove the file when the sheet closes.
            sheet.completionWithItemsHandler = { _, _, _, _ in self.finish(id, presented: true) }
        }

        private static func presentedChain(from root: UIViewController) -> [UIViewController] {
            var chain: [UIViewController] = []
            var next = root.presentedViewController
            while let controller = next {
                chain.append(controller)
                next = controller.presentedViewController
            }
            return chain
        }

        /// Once per payload: the completion handler can run again for some activities.
        func finish(_ id: SharePayload.ID, presented: Bool) {
            guard finishedID != id else { return }
            finishedID = id
            if presented { onFinish() } else { onCouldNotPresent() }
        }
    }
}
