import Foundation

/// The split rule's Savings: the transfer an income makes into the savings
/// wallet. `KeaserStore.saveIncome` keeps it in step with the income in the
/// same save.
public enum SavingsSplit {
    /// The savings transfer `income` makes, and the percentage applied, or
    /// (nil, nil) for none. `stored` is the income as the account has it,
    /// nil for a new one. `existing` is the transfer it made before: money
    /// that already moved, so it changes only with what the income
    /// changed, never with today's rates or a wallet deleted since.
    /// 1. None when the income skips it (Skip This Time).
    /// 2. The percentage is the income's own when it has one (an income
    ///    keeps the split it was logged with; nil on the copy saved keeps
    ///    the stored one's). Without one, the rule's, while the rule is on
    ///    and valid, but only for a new income or one whose Skip This
    ///    Time was just turned off: any other income was logged without a
    ///    split and stays so, whatever the rule says now, so editing an
    ///    old income never makes a transfer back then. 0 is none.
    /// 3. It goes from the income's wallet to `existing`'s wallet, or for a
    ///    new one, the rule's savings wallet: two wallets of the account.
    ///    None when the income went into no wallet, or into that wallet.
    ///    A wallet of `existing` deleted since leaves `existing` as it is.
    /// 4. The amount is that percentage of the income, rounded to the
    ///    income's currency; nothing to move is none.
    /// 5. What leaves unchanged (amount, currency, wallet, saved rate)
    ///    leaves `existing` as it is, only dated with the income. Otherwise
    ///    what arrives is the amount in the savings wallet's currency at
    ///    the income's saved rate, so both sides are worth the same, or at
    ///    today's rates without one. When it cannot be converted,
    ///    `existing` stays as it is and a new one is none.
    /// 6. It keeps `existing`'s ID, creation time and note, and is dated
    ///    with the income. Its currencies follow its wallets (nil), except
    ///    that an income in another currency than its wallet's gives the
    ///    transfer that currency, so the amount is never read in another.
    ///    `updatedAt` is `now` only when something changed.
    public static func transfer(
        for income: Income,
        stored: Income?,
        existing: Transfer?,
        in account: Account,
        rule: SplitRule,
        display: String,
        converter: CurrencyConverter,
        now: Date,
        newID: () -> UUID = UUID.init
    ) -> (transfer: Transfer?, percent: Int?) {
        let none: (transfer: Transfer?, percent: Int?) = (nil, nil)
        guard !income.savingsSkipped else { return none }
        let percent: Int
        // New, or skipped until now (this copy is not).
        let takesTheRule = stored?.savingsSkipped ?? true
        if let own = income.savingsPercent ?? stored?.savingsPercent {
            percent = own
        } else if takesTheRule, rule.isEnabled, rule.isValid {
            percent = rule.savingsPercent
        } else {
            return none
        }
        guard (1...100).contains(percent) else { return none }
        let kept = existing.map { (transfer: Optional($0), percent: Optional(percent)) } ?? none
        guard let wallet = account.paymentMethod(id: income.walletID) else {
            // The income's wallet was deleted (the transfer's with it): the
            // money left it all the same. Taken out of a wallet that is
            // still there, the income moves no money.
            guard let existing, account.paymentMethod(id: existing.fromWalletID) == nil else { return none }
            return kept
        }
        let to = existing == nil ? rule.savingsWalletID : existing?.toWalletID
        guard let target = account.paymentMethod(id: to) else { return kept }
        guard target.id != wallet.id else { return none }
        let currency = account.effectiveCurrency(of: income, display: display)
        let amountOut = CurrencyMath.rounded(income.amount * Decimal(percent) / 100, currencyCode: currency)
        guard amountOut > 0 else { return none }
        if let existing, existing.fromWalletID == wallet.id, existing.amountOut == amountOut, existing.rate == income.rate,
           CurrencyConverter.same(account.effectiveCurrencyOut(of: existing, display: display), currency) {
            var same = existing
            same.kind = .savings
            same.date = income.date
            same.incomeID = income.id
            if same != existing { same.updatedAt = now }
            return (same, percent)
        }
        guard let amountIn = converter.convert(amountOut, from: currency, to: target.effectiveCurrency(display: display), saved: income.rate)
        else { return kept }
        let walletCurrency = wallet.effectiveCurrency(display: display)
        let transfer = Transfer(
            id: existing?.id ?? newID(),
            kind: .savings,
            fromWalletID: wallet.id,
            toWalletID: target.id,
            amountOut: amountOut,
            currencyOut: CurrencyConverter.same(walletCurrency, currency) ? nil : currency,
            amountIn: amountIn,
            // What left is in the income's currency, so the income's saved
            // rate to the display currency is the transfer's too.
            rate: income.rate,
            date: income.date,
            note: existing?.note ?? "",
            incomeID: income.id,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        return (transfer, percent)
    }
}
