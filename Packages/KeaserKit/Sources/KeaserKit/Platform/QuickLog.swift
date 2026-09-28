import Foundation

/// Building expenses that arrive from outside the app: the "Add Expense"
/// shortcut and the Apple Wallet automation ("Log Wallet Transaction").
public enum QuickLog {
    /// Title used when a shortcut leaves the title empty.
    public static let defaultTitle = "Expense"

    /// A Shortcuts decimal ("16.99" arrives as a `Double`) as money, rounded to
    /// the currency's own number of fraction digits. Nil for anything that is
    /// not a positive, finite amount.
    public static func amount(from value: Double, currencyCode: String) -> Decimal? {
        guard value.isFinite, value > 0,
              // `description` is the shortest text that round-trips, so 16.99
              // becomes exactly 16.99 rather than 16.989999999999998.
              let decimal = Decimal(string: value.description, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        return amount(fromDecimal: decimal, currencyCode: currencyCode)
    }

    /// The amount the shortcut asks for (a currency amount), rounded to the
    /// currency's own number of fraction digits. Nil unless it is positive.
    /// Keaser keeps a single currency, so the currency typed with the amount
    /// is not converted.
    public static func amount(fromDecimal value: Decimal, currencyCode: String) -> Decimal? {
        let rounded = round(value, currencyCode: currencyCode)
        return rounded > 0 ? rounded : nil
    }

    /// Wallet passes the amount as text, in its own number style, which need
    /// not be the phone's ("$4.50", "4,50 €", "RWF 5,000"). Read by
    /// `WalletAmount` (a number with no currency named is taken to be in
    /// `currencyCode`), then rounded to `currencyCode`. Nil unless it is a
    /// positive number.
    public static func amount(from text: String, currencyCode: String, locale: Locale = .current) -> Decimal? {
        guard let paid = WalletAmount.read(text, currencyCode: currencyCode, locale: locale) else { return nil }
        return amount(fromDecimal: paid.value, currencyCode: currencyCode)
    }

    /// Said after the Add Expense shortcut adds an expense when nothing is
    /// shown (Siri without the screen): "Added $16.99 for Coffee to
    /// Personal." Without a title, or with the default one: "Added $16.99
    /// to Personal."
    public static func confirmation(amount: Decimal, currencyCode: String, accountName: String, title: String? = nil, locale: Locale = .current) -> String {
        let money = MoneyFormat.string(amount, currencyCode: currencyCode, locale: locale)
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, title != defaultTitle else { return "Added \(money) to \(accountName)." }
        return "Added \(money) for \(title) to \(accountName)."
    }

    /// Asked instead of showing the confirmation card when nothing is shown
    /// (Siri without the screen), so every detail is heard: "Add $19.90 for
    /// Uniqlo to Personal, under Shopping, paid with Credit Card?" A date
    /// other than today is said too.
    public static func confirmationQuestion(
        for expense: Expense,
        in account: Account,
        currencyCode: String,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let money = MoneyFormat.string(expense.amount, currencyCode: currencyCode, locale: locale)
        var text = expense.title == defaultTitle || expense.title.isEmpty
            ? "Add \(money) to \(account.name)"
            : "Add \(money) for \(expense.title) to \(account.name)"
        if let category = account.category(id: expense.categoryID) { text += ", under \(category.name)" }
        if let method = account.paymentMethod(id: expense.paymentMethodID) { text += ", paid with \(method.name)" }
        if !calendar.isDate(expense.date, inSameDayAs: now) {
            var style = Date.FormatStyle.dateTime.month(.wide).day().year().locale(locale)
            style.timeZone = calendar.timeZone
            text += ", dated \(expense.date.formatted(style))"
        }
        return text + "?"
    }

    /// The most recent expense with this title, ignoring case, accents and
    /// surrounding spaces. Wallet merchants repeat ("Blue Bottle Coffee"), so
    /// the last one tells us how the user filed it.
    public static func mostRecentExpense(titled title: String, in account: Account) -> Expense? {
        let key = normalized(title)
        guard !key.isEmpty else { return nil }
        return account.expensesNewestFirst.first { normalized($0.title) == key }
    }

    /// The payment method whose name matches the Wallet card name, if any:
    /// an exact match first, then one name containing the other, then the
    /// method sharing the most distinctive words ("Debit Mastercard" finds
    /// "Debit Card").
    public static func paymentMethod(forCard card: String?, in account: Account) -> PaymentMethod? {
        guard let card else { return nil }
        let key = normalized(card)
        guard !key.isEmpty else { return nil }
        let methods = account.paymentMethods
        if let exact = methods.first(where: { normalized($0.name) == key }) { return exact }

        let containing = methods.filter {
            let name = normalized($0.name)
            return !name.isEmpty && (key.contains(name) || name.contains(key))
        }
        if let longest = containing.max(by: { $0.name.count < $1.name.count }) { return longest }

        let cardWords = distinctiveWords(key)
        var best: (method: PaymentMethod, score: Int)?
        for method in methods {
            let score = distinctiveWords(normalized(method.name)).intersection(cardWords).count
            if score > 0, score > (best?.score ?? 0) { best = (method, score) }
        }
        return best?.method
    }

    /// The expense for a Wallet transaction: titled after the merchant, filed
    /// like the last expense with that title, paid with the matching card when
    /// the card name is recognised.
    public static func walletExpense(merchant: String, amount: Decimal, card: String?, in account: Account, now: Date = .now) -> Expense {
        let title = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = mostRecentExpense(titled: title, in: account)
        // A category or method deleted since the last expense must not come back.
        let category = account.category(id: previous?.categoryID)
        let method = paymentMethod(forCard: card, in: account) ?? account.paymentMethod(id: previous?.paymentMethodID)
        return Expense(
            title: title.isEmpty ? defaultTitle : title,
            amount: amount,
            categoryID: category?.id,
            paymentMethodID: method?.id,
            date: now,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: Shortcut labels

    // A shortcut remembers its Category and Payment Method by ID, and every
    // account has its own IDs. The system looks those IDs up again whenever
    // the shortcut runs or is edited, so the lookup searches every account,
    // not only the one selected now; the expense is then filed under the
    // target account's label with the same name.

    /// The categories with these IDs, from any account.
    public static func categories(withIDs ids: [UUID], in database: Database) -> [ExpenseCategory] {
        let wanted = Set(ids)
        return database.accounts.flatMap(\.categories).filter { wanted.contains($0.id) }
    }

    /// The payment methods with these IDs, from any account.
    public static func paymentMethods(withIDs ids: [UUID], in database: Database) -> [PaymentMethod] {
        let wanted = Set(ids)
        return database.accounts.flatMap(\.paymentMethods).filter { wanted.contains($0.id) }
    }

    /// The category of `account` a shortcut's choice stands for: the same
    /// one when it belongs to `account`, otherwise the one with the same name.
    public static func category(id: UUID, name: String, in account: Account) -> ExpenseCategory? {
        account.categories.first { $0.id == id } ?? account.categories.first { normalized($0.name) == normalized(name) }
    }

    /// The payment method of `account` a shortcut's choice stands for, matched
    /// like `category(id:name:in:)`.
    public static func paymentMethod(id: UUID, name: String, in account: Account) -> PaymentMethod? {
        account.paymentMethods.first { $0.id == id } ?? account.paymentMethods.first { normalized($0.name) == normalized(name) }
    }

    // MARK: Private

    private static func round(_ amount: Decimal, currencyCode: String) -> Decimal {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, formatter.maximumFractionDigits, .plain)
        return result
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Words that say something about which card it is. "Card" says nothing.
    private static func distinctiveWords(_ text: String) -> Set<String> {
        let generic: Set<String> = ["card", "cards", "pay", "the", "my"]
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return Set(words.filter { $0.count > 1 && !generic.contains($0) })
    }
}
