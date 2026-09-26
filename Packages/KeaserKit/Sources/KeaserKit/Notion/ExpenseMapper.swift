import Foundation

/// What a Notion row says, in Keaser terms. Fields whose property is not
/// mapped are nil and never touch the local expense.
public struct RemoteExpense: Hashable, Sendable {
    public var title: String
    /// Nil when no amount property is mapped.
    public var amount: Decimal??
    /// Outer nil: not mapped. Inner nil: mapped but empty.
    public var categoryName: String??
    public var paymentMethodName: String??
    /// "yyyy-MM-dd". Outer nil: not mapped. Inner nil: empty in Notion.
    public var day: String??

    public init(title: String, amount: Decimal?? = nil, categoryName: String?? = nil, paymentMethodName: String?? = nil, day: String?? = nil) {
        self.title = title
        self.amount = amount
        self.categoryName = categoryName
        self.paymentMethodName = paymentMethodName
        self.day = day
    }

    /// An empty row (no title, no amount): Notion databases often keep a
    /// blank row around, which should not become a $0 expense.
    public var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ((amount ?? nil) ?? 0) == 0
    }
}

/// Converts between expenses and Notion page properties for one account and
/// one property map. Categories and payment methods travel by name.
public struct ExpenseMapper: Sendable {
    public var map: NotionResolvedMap
    /// Days are written and read in this calendar's time zone.
    public var calendar: Calendar

    public init(map: NotionResolvedMap, calendar: Calendar) {
        self.map = map
        self.calendar = calendar
    }

    // MARK: Expense to Notion

    /// Every mapped property, keyed by property name. Empty values clear the
    /// Notion side, so a removed category is removed there too.
    public func properties(for expense: Expense, in account: Account) -> [String: NotionPropertyWrite] {
        var result: [String: NotionPropertyWrite] = [map.title.name: .title(expense.title)]
        if let amount = map.amount {
            result[amount.name] = .number(expense.amount)
        }
        if let property = map.category {
            result[property.name] = Self.write(account.category(id: expense.categoryID)?.name, as: property.type)
        }
        if let property = map.paymentMethod {
            result[property.name] = Self.write(account.paymentMethod(id: expense.paymentMethodID)?.name, as: property.type)
        }
        if let date = map.date {
            result[date.name] = .date(dayString(expense.date))
        }
        return result
    }

    private static func write(_ name: String?, as type: NotionPropertyType) -> NotionPropertyWrite {
        let name = name.map(NotionSelectName.sanitized).flatMap { $0.isEmpty ? nil : $0 }
        switch type {
        case .richText: return .richText(name ?? "")
        case .multiSelect: return .multiSelect(name.map { [$0] } ?? [])
        default: return .select(name)
        }
    }

    // MARK: Notion to expense

    public func remoteExpense(from page: NotionPage) -> RemoteExpense {
        func value(_ property: NotionPropertySchema?) -> NotionPropertyValue? {
            guard let property else { return nil }
            return page.properties[property.name] ?? page.properties.values.first { $0.id == property.id }
        }
        func label(_ property: NotionPropertySchema?) -> String?? {
            guard let property else { return nil }
            guard let value = value(property) else { return .some(nil) }
            let raw = value.type == .richText ? value.text : value.names.first
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .some(trimmed.isEmpty ? nil : trimmed)
        }
        let title = page.properties.values.first { $0.type == .title }?.text ?? ""
        return RemoteExpense(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: map.amount.map { value($0)?.number },
            categoryName: label(map.category),
            paymentMethodName: label(map.paymentMethod),
            day: map.date.map { value($0)?.dateStart.map { String($0.prefix(10)) } }
        )
    }

    /// Whether the page already says what the expense says, looking only at
    /// mapped properties.
    public func matches(_ expense: Expense, _ remote: RemoteExpense, in account: Account) -> Bool {
        guard expense.title.trimmingCharacters(in: .whitespacesAndNewlines) == remote.title else { return false }
        if let amount = remote.amount, expense.amount != (amount ?? 0) { return false }
        if let name = remote.categoryName,
           !NotionSelectName.same(account.category(id: expense.categoryID)?.name, name) { return false }
        if let name = remote.paymentMethodName,
           !NotionSelectName.same(account.paymentMethod(id: expense.paymentMethodID)?.name, name) { return false }
        if let day = remote.day, day != dayString(expense.date) { return false }
        return true
    }

    public func matches(_ expense: Expense, _ page: NotionPage, in account: Account) -> Bool {
        matches(expense, remoteExpense(from: page), in: account)
    }

    /// Writes the page's values into the expense. A category or payment
    /// method Keaser does not have yet is created in the account. Returns
    /// whether anything changed; `updatedAt` is left to the caller.
    @discardableResult
    public func apply(_ remote: RemoteExpense, to expense: inout Expense, in account: inout Account) -> Bool {
        let before = expense
        expense.title = remote.title
        if let amount = remote.amount { expense.amount = max(0, amount ?? 0) }
        if let name = remote.categoryName {
            expense.categoryID = name.map { categoryID(named: $0, in: &account) }
        }
        if let name = remote.paymentMethodName {
            expense.paymentMethodID = name.map { paymentMethodID(named: $0, in: &account) }
        }
        if let day = remote.day ?? nil, let date = date(fromDay: day) {
            // Keep the stored time of day when only the day is the same.
            if dayString(expense.date) != day { expense.date = date }
        }
        return expense != before
    }

    /// A new local expense for a row that only exists in Notion.
    public func makeExpense(from page: NotionPage, in account: inout Account) -> Expense {
        var expense = Expense(
            title: "",
            amount: 0,
            date: calendar.startOfDay(for: page.createdTime),
            createdAt: page.createdTime,
            updatedAt: page.lastEditedTime,
            notionPageID: page.id
        )
        apply(remoteExpense(from: page), to: &expense, in: &account)
        return expense
    }

    // MARK: Days

    public func dayString(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    public func date(fromDay day: String) -> Date? {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: Names

    private func categoryID(named name: String, in account: inout Account) -> UUID {
        if let match = account.categories.first(where: { NotionSelectName.same($0.name, name) }) { return match.id }
        let category = ExpenseCategory(name: name, symbol: NotionSymbolGuess.category(for: name))
        account.categories.append(category)
        return category.id
    }

    private func paymentMethodID(named name: String, in account: inout Account) -> UUID {
        if let match = account.paymentMethods.first(where: { NotionSelectName.same($0.name, name) }) { return match.id }
        let method = PaymentMethod(name: name, symbol: NotionSymbolGuess.paymentMethod(for: name))
        account.paymentMethods.append(method)
        return method.id
    }
}

/// A sensible SF Symbol for a category or payment method that arrived from
/// Notion, guessed from its name.
public enum NotionSymbolGuess {
    public static func category(for name: String) -> String {
        guess(name, from: categoryRules) ?? "tag.fill"
    }

    public static func paymentMethod(for name: String) -> String {
        guess(name, from: paymentRules) ?? "creditcard.fill"
    }

    private static func guess(_ name: String, from rules: [(words: [String], symbol: String)]) -> String? {
        let key = name.lowercased()
        return rules.first { rule in rule.words.contains { key.contains($0) } }?.symbol
    }

    private static let categoryRules: [(words: [String], symbol: String)] = [
        (["coffee", "cafe", "café"], "cup.and.saucer.fill"),
        (["food", "restaurant", "lunch", "dinner", "breakfast", "meal", "drink", "eat"], "fork.knife"),
        (["grocer", "supermarket"], "cart.fill"),
        (["cloth", "fashion", "apparel"], "tshirt.fill"),
        (["shop"], "bag.fill"),
        (["travel", "flight", "hotel", "trip", "vacation", "holiday"], "airplane"),
        (["fuel", "gas", "petrol"], "fuelpump.fill"),
        (["transport", "taxi", "uber", "car", "parking", "commute", "bus", "train"], "car.fill"),
        (["gym", "fitness", "sport"], "dumbbell.fill"),
        (["health", "medical", "doctor", "pharmacy", "medicine"], "cross.case.fill"),
        (["movie", "cinema", "film"], "film.fill"),
        (["music", "concert"], "music.note"),
        (["entertain", "game", "fun", "hobby"], "gamecontroller.fill"),
        (["rent", "home", "house", "mortgage", "household"], "house.fill"),
        (["electric", "utilit", "power", "energy"], "bolt.fill"),
        (["internet", "wifi", "phone", "mobile"], "wifi"),
        (["subscription", "membership"], "repeat"),
        (["service", "repair", "maintenance"], "wrench.and.screwdriver.fill"),
        (["education", "school", "course", "tuition"], "graduationcap.fill"),
        (["book"], "book.fill"),
        (["gift", "present", "donation", "charity"], "gift.fill"),
        (["pet", "dog", "cat"], "pawprint.fill"),
        (["kid", "child", "baby"], "figure.and.child.holdinghands"),
    ]

    private static let paymentRules: [(words: [String], symbol: String)] = [
        (["debit"], "creditcard.and.123"),
        (["credit", "card", "visa", "mastercard", "amex"], "creditcard.fill"),
        (["cash"], "banknote.fill"),
        (["bank", "transfer", "wire", "check", "cheque"], "building.columns.fill"),
        (["wallet", "pay", "paypal", "venmo", "mobile"], "wallet.bifold.fill"),
    ]
}
