import SwiftUI

/// Small "Privacy · Terms" links under the unlock, opened in the app. Just "Terms" until
/// `AppInfo.privacyPolicyURL` is set.
struct LegalLinks: View {
    @State private var link: SafariLink?

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let privacy = AppInfo.privacyPolicyURL {
                linkButton("Privacy", url: privacy, id: "legal.privacy")
                Text("·")
                    .accessibilityHidden(true)
            }
            linkButton("Terms", url: AppInfo.termsURL, id: "legal.terms")
        }
        .font(.footnote)
        .foregroundStyle(DS.Palette.secondary)
        .frame(maxWidth: .infinity)
        .safariSheet($link)
    }

    private func linkButton(_ title: String, url: URL, id: String) -> some View {
        Button(title) { link = SafariLink(url: url) }
            .frame(minHeight: 44)
            .accessibilityLabel(title == "Terms" ? "Terms of use" : "Privacy policy")
            .accessibilityIdentifier(id)
    }
}
