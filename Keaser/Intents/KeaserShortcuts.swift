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
    }
}
