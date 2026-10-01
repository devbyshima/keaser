import KeaserKit
import SwiftUI
import UIKit

/// The Home tab: account switcher, search, filters, the spending summary with
/// its chart, the latest expenses and the add button. Search replaces all of
/// it with its own full-screen view while it is open, and the tab bar hides
/// meanwhile.
struct HomeView: View {
    @Environment(KeaserStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The moment the totals and chart are worked out for. Kept in state and
    /// refreshed at midnight, on time zone or clock changes and on returning
    /// to the app, so "Spent today" and "Spent this month" roll over without
    /// the user touching anything.
    @State private var now = Date.now

    // Filters live here, not in preferences: they reset whenever the account
    // changes. A nil period means "the default for the current plan".
    @State private var periodChoice: Period?
    @State private var categoryFilter: UUID?
    @State private var paymentFilter: UUID?

    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    @State private var sheet: HomeSheet?
    @State private var expenseToDelete: Expense?
    @State private var deletedCount = 0
    #if DEBUG
    @State private var didApplyDebugLaunch = false
    #endif

    var body: some View {
        ZStack {
            Color.keaserBackground.ignoresSafeArea()
            if let account = store.selectedAccount {
                if isSearching {
                    searchScreen(account)
                        .transition(.opacity)
                } else {
                    accountScreen(account)
                        .transition(.opacity)
                }
            } else {
                noAccountScreen
                    .transition(.opacity)
            }
        }
        // Search keeps the whole screen, its field at the bottom as in the
        // reference, so the tab bar steps aside while it is open.
        // Only while Home shows: a route to Settings leaves Search open
        // behind it, and the bar must come back there.
        .toolbarVisibility(isSearching && router.selectedTab == .home ? .hidden : .visible, for: .tabBar)
        .animation(.smooth(duration: 0.35), value: store.selectedAccount == nil)
        // Switching accounts, from the Accounts sheet or by creating one,
        // animates everything that depends on the account at once: the
        // total rolls to its new value, the bars grow or shrink, the rows
        // cross-fade and the account name in the top bar fades across.
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.5), value: store.selectedAccount?.id)
        .sheet(item: $sheet) { presented in
            sheetContent(presented)
        }
        .confirmationDialog(
            "Delete Expense?",
            isPresented: Binding(get: { expenseToDelete != nil }, set: { if !$0 { expenseToDelete = nil } }),
            titleVisibility: .visible,
            presenting: expenseToDelete
        ) { expense in
            Button("Delete Expense", role: .destructive) { delete(expense) }
            Button("Cancel", role: .cancel) {}
        } message: { expense in
            Text("\u{201C}\(expense.title)\u{201D} will be removed from this account.")
        }
        .onChange(of: store.selectedAccount?.id) { _, _ in resetFilters() }
        .onChange(of: router.pendingRoute, initial: true) { _, route in handle(route) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now }
        }
        // The pass or a subscription can run out while Home is open; wake at
        // that moment rather than at midnight, and drop Pro-only filters.
        .task(id: nextProChange) { await refreshNow(at: nextProChange) }
        .onChange(of: pro.isPro) { _, isPro in
            if !isPro { dropProFilters() }
        }
        .sensoryFeedback(.success, trigger: deletedCount)
        #if DEBUG
        .onAppear(perform: applyDebugLaunch)
        #endif
    }

    // MARK: Screens

    private var noAccountScreen: some View {
        EmptyStateView(
            symbol: "person.crop.circle",
            title: "No Account",
            message: "Add an account to start tracking expenses.",
            style: .large
        ) {
            Button("Add Account") { sheet = .addAccount }
                .buttonStyle(.keaserCapsule(height: 36, horizontalPadding: 11))
                // The style taps across 44pt; lay it out at the drawn 36pt so
                // the block sits where the reference has it.
                .padding(.vertical, -4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func accountScreen(_ account: Account) -> some View {
        let filter = currentFilter(for: account)
        let calendar = store.preferences.calendar
        let expenses = ExpenseQuery.apply(filter, to: account.expenses, now: now, calendar: calendar)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if account.expenses.isEmpty {
                    EmptyStateView(
                        symbol: "creditcard",
                        title: "No Expenses",
                        message: "Add your first expense by tapping the + button",
                        style: .large
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, HomeLayout.emptyStateTop - HomeLayout.contentTop)
                } else {
                    HomeSummaryCard(
                        caption: filter.period.spentCaption,
                        total: ExpenseQuery.total(of: expenses),
                        currencyCode: store.preferences.currencyCode,
                        period: filter.period,
                        calendar: calendar,
                        buckets: SpendingChart.buckets(for: expenses, period: filter.period, now: now, calendar: calendar)
                    )
                    latestSection(expenses, in: account, filter: filter)
                }
            }
            .padding(.horizontal, KeaserMetrics.screenPadding)
            .padding(.top, HomeLayout.contentTop)
            .padding(.bottom, HomeLayout.addButtonSize + 48)
            .animation(.smooth(duration: 0.3), value: expenses.map(\.id))
        }
        .scrollIndicators(.hidden)
        .keaserSwipeActionsContainer()
        .keaserReadableScrollContent()
        .safeAreaInset(edge: .top, spacing: 0) {
            HomeTopBar(
                accountName: account.name,
                onAccounts: { sheet = .accounts },
                onSearch: beginSearch
            ) {
                HomeFilterMenu(
                    account: account,
                    period: filter.period,
                    categoryID: filter.categoryID,
                    paymentMethodID: filter.paymentMethodID,
                    isPro: pro.isPro,
                    onPeriod: choosePeriod,
                    onCategory: chooseCategory,
                    onPaymentMethod: choosePaymentMethod
                )
            }
            .keaserEntity(account: account.id)
        }
        .overlay(alignment: .bottomTrailing) {
            HomeAddButton { sheet = .newExpense }
                .padding(.trailing, HomeLayout.addButtonTrailing)
                .padding(.bottom, HomeLayout.addButtonBottom)
                .keaserReadableWidth(alignment: .trailing)
        }
    }

    @ViewBuilder
    private func latestSection(_ expenses: [Expense], in account: Account, filter: ExpenseQuery.Filter) -> some View {
        Text("Latest")
            .keaserFont(17, weight: .semibold, relativeTo: .headline)
            .foregroundStyle(Color.keaserSecondaryText)
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, 16)
            .padding(.top, 28)
            .padding(.bottom, 9.5)
        if expenses.isEmpty {
            Text(filter.narrowsByLabel ? "No expenses match these filters." : "No expenses \(filter.period.emptyPhrase).")
                .font(.subheadline)
                .foregroundStyle(Color.keaserSecondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
        HomeExpenseRows(
            expenses: expenses,
            account: account,
            currencyCode: store.preferences.currencyCode,
            onOpen: { sheet = .expense($0.id) },
            onEdit: { sheet = .editExpense($0.id) },
            onDelete: { expenseToDelete = $0 }
        )
    }

    /// Search looks through what Home's filters show (the period, category
    /// and payment method), live as the text changes.
    private func searchScreen(_ account: Account) -> some View {
        HomeSearchView(
            account: account,
            result: ExpenseQuery.search(
                searchText,
                filter: currentFilter(for: account),
                in: account.expenses,
                now: now,
                calendar: store.preferences.calendar
            ),
            currencyCode: store.preferences.currencyCode,
            text: $searchText,
            isFocused: $searchFocused,
            onOpen: { sheet = .expense($0.id) },
            onEdit: { sheet = .editExpense($0.id) },
            onDelete: { expenseToDelete = $0 },
            onClose: endSearch
        )
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ presented: HomeSheet) -> some View {
        switch presented {
        case .accounts:
            AccountsSheet()
        case .addAccount:
            AddAccountSheet()
        case .newExpense:
            if let account = store.selectedAccount {
                ExpenseEditorView(accountID: account.id)
            }
        case .scanReceipt:
            if let account = store.selectedAccount {
                ExpenseEditorView(accountID: account.id, scansReceipt: true)
            }
        case .editExpense(let id):
            if let account = store.selectedAccount, let expense = account.expenses.first(where: { $0.id == id }) {
                ExpenseEditorView(accountID: account.id, expense: expense)
            }
        case .expense(let id):
            if let account = store.selectedAccount, account.expenses.contains(where: { $0.id == id }) {
                ExpenseDetailSheet(accountID: account.id, expenseID: id)
            }
        case .paywall(let feature):
            PaywallView(highlighting: feature)
        }
    }

    // MARK: Filters

    private func currentFilter(for account: Account) -> ExpenseQuery.Filter {
        let isPro = pro.isPro
        let filter = ExpenseQuery.Filter(
            period: periodChoice ?? ExpenseQuery.Filter.initial(isPro: isPro).period,
            categoryID: categoryFilter.flatMap { account.category(id: $0)?.id },
            paymentMethodID: paymentFilter.flatMap { account.paymentMethod(id: $0)?.id }
        )
        // A lapsed pass never shows locked data, even before
        // `dropProFilters` has reset the choices.
        return isPro ? filter : filter.withoutPro
    }

    private func choosePeriod(_ period: Period) {
        guard !period.isLongTerm || pro.isPro else {
            sheet = .paywall(.longTermInsights)
            return
        }
        withAnimation(.smooth(duration: 0.35)) { periodChoice = period }
    }

    private func chooseCategory(_ id: UUID?) {
        guard id == nil || pro.isPro else {
            sheet = .paywall(.moreFilters)
            return
        }
        withAnimation(.smooth(duration: 0.35)) { categoryFilter = id }
    }

    private func choosePaymentMethod(_ id: UUID?) {
        guard id == nil || pro.isPro else {
            sheet = .paywall(.moreFilters)
            return
        }
        withAnimation(.smooth(duration: 0.35)) { paymentFilter = id }
    }

    /// Pro ended while Home was open: a long-term period goes back to This
    /// Month and the category and payment filters to All. The fallback is
    /// kept as the choice, so buying Pro later does not switch the period
    /// under the user.
    private func dropProFilters() {
        let shown = ExpenseQuery.Filter(
            period: periodChoice ?? ExpenseQuery.Filter.initial(isPro: true).period,
            categoryID: categoryFilter,
            paymentMethodID: paymentFilter
        ).withoutPro
        withAnimation(.smooth(duration: 0.35)) {
            periodChoice = shown.period
            categoryFilter = shown.categoryID
            paymentFilter = shown.paymentMethodID
        }
    }

    /// When Pro next ends by itself (the pass or a cached subscription
    /// running out), or nil when nothing is due to end.
    private var nextProChange: Date? {
        ProEntitlement.nextChange(after: now, preferences: store.preferences)
    }

    /// Moves `now` on once `date` has passed, which re-checks Pro and starts
    /// the wait for the next change.
    private func refreshNow(at date: Date?) async {
        guard let date else { return }
        // A second late, so the entitlement has certainly ended by then.
        try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow) + 1))
        guard !Task.isCancelled else { return }
        now = .now
    }

    private func resetFilters() {
        periodChoice = nil
        categoryFilter = nil
        paymentFilter = nil
        endSearch()
    }

    // MARK: Search

    private func beginSearch() {
        searchText = ""
        withAnimation(.smooth(duration: 0.25)) { isSearching = true }
        // The field only exists after this update, so focus it on the next.
        Task { @MainActor in searchFocused = true }
    }

    private func endSearch() {
        searchFocused = false
        withAnimation(.smooth(duration: 0.25)) {
            isSearching = false
            searchText = ""
        }
    }

    // MARK: Actions

    private func delete(_ expense: Expense) {
        guard let account = store.selectedAccount else { return }
        withAnimation(.smooth(duration: 0.3)) {
            store.deleteExpense(expense.id, in: account.id)
        }
        deletedCount += 1
    }

    /// Follows a route `AppRouter.open` left. Home's own routes come once
    /// the Home tab shows. `.settings` comes before the Settings tab does,
    /// and Home only closes what it presents: a sheet left up would hide
    /// that tab, and would stick once Home left the screen.
    private func handle(_ route: AppRouter.Route?) {
        guard let route else { return }
        expenseToDelete = nil
        switch route {
        case .newExpense:
            sheet = store.selectedAccount == nil ? .addAccount : .newExpense
        case .scanReceipt:
            sheet = store.selectedAccount == nil ? .addAccount : .scanReceipt
        case .settings:
            sheet = nil
        case .expense(let id):
            openExpense(id)
        case .account(let id):
            openAccount(id)
        case .search(let text):
            if store.selectedAccount != nil {
                sheet = nil
                showSearch(for: text)
            }
        }
        router.clearPendingRoute()
    }

    /// An expense opened from Siri, Shortcuts or Spotlight: its account is
    /// selected (resetting the filters, as any switch does) and the expense's
    /// details show, whatever period Home is on.
    private func openExpense(_ id: UUID) {
        guard let account = EntityCatalog.account(containingExpense: id, in: store.database) else { return }
        store.selectAccount(account.id)
        sheet = .expense(id)
    }

    /// An account opened from Siri, Shortcuts or Spotlight: selected, with
    /// Home showing and nothing over it.
    private func openAccount(_ id: UUID) {
        guard store.account(id: id) != nil else { return }
        store.selectAccount(id)
        sheet = nil
        endSearch()
    }

    /// Search opened with a term from Siri or Shortcuts. The results show
    /// straight away, with the keyboard down so they can be seen; without a
    /// term it opens as the search button does.
    private func showSearch(for text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            beginSearch()
            return
        }
        searchFocused = false
        withAnimation(.smooth(duration: 0.25)) {
            isSearching = true
            searchText = text
        }
    }

    #if DEBUG
    /// `-KeaserSheet`, `-KeaserPeriod` and `-KeaserSearch`, for screenshots.
    private func applyDebugLaunch() {
        guard !didApplyDebugLaunch else { return }
        didApplyDebugLaunch = true
        if let period = DebugLaunch.string("KeaserPeriod").flatMap(Period.init(rawValue:)) {
            periodChoice = period
        }
        switch DebugLaunch.sheet {
        case "accounts": sheet = .accounts
        case "addAccount": sheet = .addAccount
        case "newExpense" where store.selectedAccount != nil: sheet = .newExpense
        case "editExpense":
            if let newest = store.selectedAccount?.expensesNewestFirst.first {
                sheet = .editExpense(newest.id)
            }
        case "expense":
            if let newest = store.selectedAccount?.expensesNewestFirst.first {
                sheet = .expense(newest.id)
            }
        case "search" where store.selectedAccount != nil:
            isSearching = true
            searchText = DebugLaunch.string("KeaserSearch") ?? ""
        default: break
        }
    }
    #endif
}

/// Everything Home presents as a sheet.
enum HomeSheet: Identifiable, Hashable {
    case accounts
    case addAccount
    case newExpense
    /// New Expense with the document camera up, from the Scan Receipt
    /// control.
    case scanReceipt
    /// An expense's details, read only, with Edit and Delete.
    case expense(UUID)
    case editExpense(UUID)
    case paywall(ProFeature)

    var id: Self { self }
}

private extension Period {
    /// "No expenses this month."
    var emptyPhrase: String {
        switch self {
        case .today: "today"
        case .thisWeek: "this week"
        case .thisMonth: "this month"
        case .thisYear: "this year"
        case .allTime: "yet"
        }
    }
}
