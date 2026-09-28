import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center, lock screen and Action button control that opens Keaser
/// straight on New Expense, ready to type the title.
///
/// It cannot ask the Add Expense questions where it is tapped: iOS gives a
/// control's action no way to prompt, so such a control does nothing. Siri,
/// Shortcuts and Wallet automations still run Add Expense in place.
struct AddExpenseControl: ControlWidget {
    static let kind = "com.fulltimestudio.keaser.add-expense"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "keaser://new-expense")!)) {
                Label("Add Expense", systemImage: "creditcard.fill")
            }
        }
        .displayName("Add Expense")
        .description("Open Keaser on a new expense.")
    }
}
