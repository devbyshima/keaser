import Foundation

/// Converts amounts between currencies. A transaction's converted value
/// uses the rate saved on it, so old totals never move when rates change;
/// today's table is only for today's balances and for new entries.
public struct CurrencyConverter: Hashable, Sendable {
    /// The currency totals are shown in (`Preferences.currencyCode`).
    public var displayCurrency: String
    /// Today's table, or nil before any rates were fetched.
    public var rates: ExchangeRates?

    public init(displayCurrency: String, rates: ExchangeRates?) {
        self.displayCurrency = displayCurrency
        self.rates = rates
    }

    /// `amount` of `from` in `to`, in that order of preference:
    /// 1. The same currency: the amount as it is.
    /// 2. A saved rate into `to`: amount x saved rate.
    /// 3. A saved rate into another currency the table converts to `to`:
    ///    amount x saved rate x table rate.
    /// 4. The table converts `from` to `to`: amount x table rate.
    /// 5. Otherwise nil: it cannot be converted. Callers count it and
    ///    leave it out, never guess.
    ///
    /// Converted amounts are rounded to `to`'s places. A saved rate of 0 or
    /// without a currency counts as none.
    public func convert(_ amount: Decimal, from: String, to: String, saved: ExchangeRate?) -> Decimal? {
        if Self.same(from, to) { return amount }
        if let saved, saved.isUsable {
            if Self.same(saved.currencyCode, to) {
                return CurrencyMath.rounded(amount * saved.rate, currencyCode: to)
            }
            if let table = rates?.rate(from: saved.currencyCode, to: to) {
                return CurrencyMath.rounded(amount * saved.rate * table, currencyCode: to)
            }
        }
        if let table = rates?.rate(from: from, to: to) {
            return CurrencyMath.rounded(amount * table, currencyCode: to)
        }
        return nil
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.uppercased() == b.uppercased()
    }
}

// MARK: - Effective currencies

/// What currency each thing is in once the nils are filled in. A nil code
/// means "whatever my wallet is in", and a wallet's nil code means the
/// display currency, so these are the one place that decides it.
extension Account {
    /// A wallet's currency; nil when the account has no such wallet.
    public func effectiveCurrency(ofWallet id: UUID?, display: String) -> String? {
        paymentMethod(id: id)?.effectiveCurrency(display: display)
    }

    /// Its own code, else its wallet's currency, else the display currency.
    public func effectiveCurrency(of expense: Expense, display: String) -> String {
        expense.currencyCode ?? effectiveCurrency(ofWallet: expense.paymentMethodID, display: display) ?? display
    }

    /// Its own code, else its wallet's currency, else the display currency.
    public func effectiveCurrency(of income: Income, display: String) -> String {
        income.currencyCode ?? effectiveCurrency(ofWallet: income.walletID, display: display) ?? display
    }

    /// The currency of `amountOut`: its own code, else the from wallet's,
    /// else the display currency.
    public func effectiveCurrencyOut(of transfer: Transfer, display: String) -> String {
        transfer.currencyOut ?? effectiveCurrency(ofWallet: transfer.fromWalletID, display: display) ?? display
    }

    /// The currency of `amountIn`: its own code, else the to wallet's,
    /// else the display currency.
    public func effectiveCurrencyIn(of transfer: Transfer, display: String) -> String {
        transfer.currencyIn ?? effectiveCurrency(ofWallet: transfer.toWalletID, display: display) ?? display
    }
}
