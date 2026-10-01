import Foundation

/// The split rule's Savings: the transfer an income makes into the savings
/// wallet. `KeaserStore.saveIncome` keeps it in step with the income in the
/// same save.
public enum SavingsSplit {
    /// The savings transfer `income` makes, and the percentage applied, or
    /// (nil, nil) for none:
    /// 1. None when the income skips it (Skip This Time) or went into no
    ///    wallet.
    /// 2. The percentage is the income's own when it has one (an income
    ///    keeps the split it was logged with), else the rule's while the
    ///    rule is on and valid. 0 is none.
    /// 3. It goes to `existing`'s wallet, else the rule's savings wallet,
    ///    which must be a wallet of the account other than the income's.
    /// 4. The amount is that percentage of the income, rounded to the
    ///    income's currency; nothing to move is none.
    /// 5. What arrives is that amount in the savings wallet's currency at
    ///    today's rates; none when it cannot be converted.
    /// 6. It keeps `existing`'s ID, creation time and note, and is dated
    ///    with the income. Its currencies follow its wallets (nil), except
    ///    that an income in another currency than its wallet's gives the
    ///    transfer that currency, so the amount is never read in another.
    public static func transfer(
        for income: Income,
        existing: Transfer?,
        in account: Account,
        rule: SplitRule,
        display: String,
        converter: CurrencyConverter,
        now: Date,
        newID: () -> UUID = UUID.init
    ) -> (transfer: Transfer?, percent: Int?) {
        let none: (transfer: Transfer?, percent: Int?) = (nil, nil)
        guard !income.savingsSkipped, let from = income.walletID else { return none }
        let percent: Int
        if let own = income.savingsPercent {
            percent = own
        } else if rule.isEnabled, rule.isValid {
            percent = rule.savingsPercent
        } else {
            return none
        }
        guard (1...100).contains(percent) else { return none }
        guard let to = existing?.toWalletID ?? rule.savingsWalletID, to != from,
              let target = account.paymentMethod(id: to)
        else { return none }
        let currency = account.effectiveCurrency(of: income, display: display)
        let amountOut = CurrencyMath.rounded(income.amount * Decimal(percent) / 100, currencyCode: currency)
        guard amountOut > 0,
              let amountIn = converter.convert(amountOut, from: currency, to: target.effectiveCurrency(display: display), saved: nil)
        else { return none }
        let walletCurrency = account.effectiveCurrency(ofWallet: from, display: display) ?? display
        let transfer = Transfer(
            id: existing?.id ?? newID(),
            kind: .savings,
            fromWalletID: from,
            toWalletID: to,
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
