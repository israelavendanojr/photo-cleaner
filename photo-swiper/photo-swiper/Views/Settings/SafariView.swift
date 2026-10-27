import SafariServices
import SwiftUI

/// A web page opened in the app, over the current screen. Used for the legal pages.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(DS.Palette.ink)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// A page to open in `SafariView`, as a sheet item.
struct SafariLink: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}

extension View {
    /// Presents `link` in an in-app Safari view while it's set.
    func safariSheet(_ link: Binding<SafariLink?>) -> some View {
        sheet(item: link) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }
}
