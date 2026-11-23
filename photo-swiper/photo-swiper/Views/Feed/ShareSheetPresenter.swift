import SwiftUI
import UIKit

/// Shows iOS's share sheet for a prepared file (JUN-8). Not `ShareLink`: the file is prepared first, on the
/// card, so an iCloud download never stalls inside Messages. Sits in the deck's background and presents
/// `UIActivityViewController` once per payload from the window's root; `onFinish` runs when the sheet
/// closes, sent or not, so the file can be removed.
///
/// The file can arrive after the user opened a viewer or a sheet, or left the Feed tab. The sheet isn't
/// put over those: `onCouldNotPresent` runs instead, as it does if UIKit refuses the presentation, so a
/// payload is never left waiting and later shares aren't blocked.
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
        let sheet = UIActivityViewController(activityItems: [payload.url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = host.view
        sheet.completionWithItemsHandler = { _, _, _, _ in coordinator.finish(payload.id, presented: true) }
        // After this update, so the host is in the window. UIKit refuses a presentation silently (and the
        // completion handler then never runs) only when the root is off screen, already presenting, or
        // mid-transition, so those are checked up front. Nothing is checked after `present`:
        // `UIActivityViewController` loads its targets first and attaches later, so an early look sees it
        // unpresented, and treating that as a refusal deleted the file under an open sheet.
        DispatchQueue.main.async {
            guard let root = host.view.window?.rootViewController, root.viewIfLoaded?.window != nil,
                  root.presentedViewController == nil, !root.isBeingPresented, !root.isBeingDismissed
            else {
                coordinator.finish(payload.id, presented: false)
                return
            }
            root.present(sheet, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var presentedID: SharePayload.ID?
        var onFinish: () -> Void = {}
        var onCouldNotPresent: () -> Void = {}
        private var finishedID: SharePayload.ID?

        /// Once per payload: the completion handler can run again for some activities.
        func finish(_ id: SharePayload.ID, presented: Bool) {
            guard finishedID != id else { return }
            finishedID = id
            if presented { onFinish() } else { onCouldNotPresent() }
        }
    }
}
