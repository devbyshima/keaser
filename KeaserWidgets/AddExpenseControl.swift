import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center, lock screen and Action button control that opens Keaser
/// straight on a new expense.
struct AddExpenseControl: ControlWidget {
    static let kind = "com.fulltimestudio.keaser.add-expense"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "keaser://new-expense")!)) {
                Label("Add Expense", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Add Expense")
        .description("Open Keaser on a new expense.")
    }
}
