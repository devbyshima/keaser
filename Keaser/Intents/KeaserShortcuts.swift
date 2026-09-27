import AppIntents

/// Shortcuts that work as soon as Keaser is installed, with no setup in the
/// Shortcuts app.
struct KeaserShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "Log an expense in \(.applicationName)",
                "Add expense to \(.applicationName)",
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: LogWalletTransactionIntent(),
            phrases: [
                "Log a transaction in \(.applicationName)",
                "Log a wallet transaction in \(.applicationName)",
            ],
            shortTitle: "Log Transaction",
            systemImageName: "wallet.bifold.fill"
        )
        AppShortcut(
            intent: SearchExpensesIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Search in \(.applicationName)",
                "Search expenses in \(.applicationName)",
            ],
            shortTitle: "Search Expenses",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenAccountIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Switch \(.applicationName) to \(\.$target)",
                "Open an account in \(.applicationName)",
            ],
            shortTitle: "Open Account",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: OpenExpenseIntent(),
            phrases: [
                "Open an expense in \(.applicationName)",
                "Show an expense in \(.applicationName)",
            ],
            shortTitle: "Open Expense",
            systemImageName: "creditcard"
        )
    }
}
