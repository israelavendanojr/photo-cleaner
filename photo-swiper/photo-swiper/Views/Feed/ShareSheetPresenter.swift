import SwiftUI
import UIKit

/// Shows iOS's share sheet for a prepared file (JUN-8). Not `ShareLink`: the file is prepared first, on the
/// card, so an iCloud download never stalls inside Messages. Sits in the deck's background and presents
/// `UIActivityViewController` once per payload; `onFinish` runs when the sheet closes, sent or not, so the
/// file can be removed. If the sheet can't be shown (something else is up), it finishes straight away.
struct ShareSheetPresenter: UIViewControllerRepresentable {
    let payload: SharePayload?
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.isUserInteractionEnabled = false
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.onFinish = onFinish
        guard let payload, context.coordinator.presentedID != payload.id else { return }
        context.coordinator.presentedID = payload.id
        let sheet = UIActivityViewController(activityItems: [payload.url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = host.view
        let coordinator = context.coordinator
        sheet.completionWithItemsHandler = { _, _, _, _ in coordinator.finish(payload.id) }
        // After this update, so the host is in the window.
        DispatchQueue.main.async {
            guard host.view.window != nil, host.presentedViewController == nil else {
                coordinator.finish(payload.id)
                return
            }
            host.present(sheet, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var presentedID: SharePayload.ID?
        var onFinish: () -> Void = {}
        private var finishedID: SharePayload.ID?

        /// Once per payload: the completion handler can run again for some activities.
        func finish(_ id: SharePayload.ID) {
            guard finishedID != id else { return }
            finishedID = id
            onFinish()
        }
    }
}
