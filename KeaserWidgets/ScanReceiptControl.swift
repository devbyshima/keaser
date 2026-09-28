import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center, lock screen and Action button control that opens Keaser
/// on New Expense with the document camera already up: photograph the
/// receipt, and the merchant, total and date fill in with the photo
/// attached, ready to check and save.
///
/// Like Add Expense, it opens the app (`keaser://scan-receipt`): a control's
/// action cannot show a camera where it is tapped.
struct ScanReceiptControl: ControlWidget {
    static let kind = "com.fulltimestudio.keaser.scan-receipt"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "keaser://scan-receipt")!)) {
                Label("Scan Receipt", systemImage: "doc.viewfinder")
            }
        }
        .displayName("Scan Receipt")
        .description("Photograph a receipt to add an expense.")
    }
}
