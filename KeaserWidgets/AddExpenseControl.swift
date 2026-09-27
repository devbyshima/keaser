import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center, lock screen and Action button control that runs the Add
/// Expense shortcut's questions right where it is tapped, without opening
/// Keaser.
struct AddExpenseControl: ControlWidget {
    static let kind = "com.fulltimestudio.keaser.add-expense"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AddExpenseIntent()) {
                Label("Add Expense", systemImage: "creditcard.fill")
            }
        }
        .displayName("Add Expense")
        .description("Add an expense without opening Keaser.")
    }
}

extension AddExpenseIntent {
    /// Only for a system that performs the intent in this extension despite
    /// `supportedModes`: nothing can be asked from here, so it says where to
    /// add the expense instead.
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Open Keaser to add this expense.")
    }
}
