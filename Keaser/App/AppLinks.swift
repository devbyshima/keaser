import Foundation

/// Where Keaser points people outside the app. Every value is optional: a nil
/// value hides the row or page that would use it, so nothing ever links to an
/// address the maker does not own. Fill these in before shipping.
enum AppLinks {
    /// Recipient for "Support Email" in Help & Feedback.
    static let supportEmail: String? = nil
    /// A public board or form for "Feature Requests".
    static let featureRequests: URL? = nil
    /// Profiles listed on "Follow Us" and at the end of the welcome letter.
    static let social: [SocialLink] = []

    struct SocialLink: Identifiable, Hashable {
        /// "X (Twitter)", "Threads", "GitHub".
        let service: String
        /// "@keaserapp".
        let handle: String
        let url: URL
        /// SF Symbol shown beside the service name.
        let symbol: String

        var id: URL { url }
    }
}
