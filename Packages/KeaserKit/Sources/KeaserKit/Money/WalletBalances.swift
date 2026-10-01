import Foundation

/// A tracked wallet's balance, in the wallet's own currency.
public struct WalletBalance: Hashable, Sendable {
    /// The money in the wallet. A credit card that owes 500 is -500.
    public var amount: Decimal
    /// Entries in another currency that could not be converted: left out
    /// of `amount`, never guessed.
    public var unconverted: Int

    public init(amount: Decimal, unconverted: Int = 0) {
        self.amount = amount
        self.unconverted = unconverted
    }
}

/// What a credit card owes and what can still be spent on it, read from
/// its balance (below 0 while it owes).
public struct CreditCardStatus: Hashable, Sendable {
    /// What is owed; 0 once the card is paid off or overpaid.
    public var owed: Decimal
    /// The limit plus the balance: more than the limit when overpaid, below
    /// 0 over the limit. Nil for a card without a limit.
    public var available: Decimal?

    public init(balance: Decimal, creditLimit: Decimal?) {
        owed = max(0, -balance)
        available = creditLimit.map { $0 + balance }
    }
}

/// Wallet balances. A balance starts from the wallet's latest checkpoint,
/// a balance the person stated (Set Balance), and moves with every entry
/// logged after it, so history is never edited to put a wallet right.
public enum WalletBalances {
    /// The balance of `walletID` in its own currency, or nil when the
    /// account has no such wallet, it is not tracking a balance, or it only
    /// started after `asOf`.
    ///
    /// - The base is the latest checkpoint: the opening one
    ///   (`trackingSince`, `openingBalance`) or a later `BalanceAdjustment`
    ///   of the wallet. Latest by date, then by when it was made.
    /// - Incomes into the wallet and transfers in add; expenses from it and
    ///   transfers out subtract. A transfer from the wallet to itself is
    ///   nothing.
    /// - An entry counts when its day (in `calendar`) is after the base's
    ///   day, or it is the same day and was logged (`createdAt`) after the
    ///   base was stated. One dated before is already in the stated
    ///   balance and never counts twice; one logged later the same day
    ///   counts.
    /// - With `asOf`, only checkpoints up to that moment, and entries dated
    ///   on its day or before.
    /// - An entry in another currency than the wallet's is converted at its
    ///   saved rate (`CurrencyConverter`); one that cannot be is left out
    ///   and counted in `unconverted`.
    public static func balance(
        of walletID: UUID,
        in account: Account,
        display: String,
        converter: CurrencyConverter,
        calendar: Calendar,
        asOf: Date? = nil
    ) -> WalletBalance? {
        guard let wallet = account.paymentMethod(id: walletID), let since = wallet.trackingSince else { return nil }
        if let asOf, since > asOf { return nil }
        let base = latestCheckpoint(of: wallet, since: since, in: account, asOf: asOf)
        let currency = wallet.effectiveCurrency(display: display)
        var result = WalletBalance(amount: base.balance)

        func add(_ amount: Decimal, in entryCurrency: String, saved: ExchangeRate?, date: Date, createdAt: Date) {
            guard counts(date: date, createdAt: createdAt, after: base.date, asOf: asOf, calendar: calendar) else { return }
            if let converted = converter.convert(amount, from: entryCurrency, to: currency, saved: saved) {
                result.amount += converted
            } else {
                result.unconverted += 1
            }
        }

        for income in account.incomes where income.walletID == walletID {
            add(income.amount, in: account.effectiveCurrency(of: income, display: display),
                saved: income.rate, date: income.date, createdAt: income.createdAt)
        }
        for expense in account.expenses where expense.paymentMethodID == walletID {
            add(-expense.amount, in: account.effectiveCurrency(of: expense, display: display),
                saved: expense.rate, date: expense.date, createdAt: expense.createdAt)
        }
        for transfer in account.transfers where transfer.fromWalletID != transfer.toWalletID {
            if transfer.toWalletID == walletID {
                let currencyIn = account.effectiveCurrencyIn(of: transfer, display: display)
                let currencyOut = account.effectiveCurrencyOut(of: transfer, display: display)
                add(transfer.amountIn, in: currencyIn,
                    saved: savedRateIn(of: transfer, currencyIn: currencyIn, currencyOut: currencyOut),
                    date: transfer.date, createdAt: transfer.createdAt)
            }
            if transfer.fromWalletID == walletID {
                add(-transfer.amountOut, in: account.effectiveCurrencyOut(of: transfer, display: display),
                    saved: transfer.rate, date: transfer.date, createdAt: transfer.createdAt)
            }
        }
        return result
    }

    /// The total of the account's tracked wallets, hidden ones left out, in
    /// the display currency. Each balance is converted at today's rates (a
    /// balance has no saved rate), and a credit card counts against the
    /// total by its negative balance. `unconverted` counts the entries left
    /// out of the balances, plus each wallet whose balance could not be
    /// converted (left out whole, counted once).
    public static func total(
        in account: Account,
        display: String,
        converter: CurrencyConverter,
        calendar: Calendar
    ) -> (amount: Decimal, unconverted: Int) {
        var amount: Decimal = 0
        var unconverted = 0
        for wallet in account.paymentMethods where wallet.isTracking && !wallet.isHidden {
            guard let balance = balance(of: wallet.id, in: account, display: display, converter: converter, calendar: calendar)
            else { continue }
            if let converted = converter.convert(balance.amount, from: wallet.effectiveCurrency(display: display), to: display, saved: nil) {
                amount += converted
                unconverted += balance.unconverted
            } else {
                unconverted += 1
            }
        }
        return (amount, unconverted)
    }

    // MARK: Checkpoints

    /// A balance the person stated: the wallet held `balance` at `date`.
    private struct Checkpoint {
        var balance: Decimal
        var date: Date
        var createdAt: Date
        var id: String
    }

    /// The latest of the opening checkpoint and the wallet's adjustments
    /// (up to `asOf`); one from before the opening (a wallet set up again)
    /// is never the latest. Ties go to the one made later, then to the
    /// greater ID, so every device picks the same one. The opening one
    /// loses every tie: an adjustment is always stated after it.
    private static func latestCheckpoint(of wallet: PaymentMethod, since: Date, in account: Account, asOf: Date?) -> Checkpoint {
        var latest = Checkpoint(balance: wallet.openingBalance, date: since, createdAt: .distantPast, id: "")
        for adjustment in account.balanceAdjustments where adjustment.walletID == wallet.id {
            if let asOf, adjustment.date > asOf { continue }
            let candidate = Checkpoint(
                balance: adjustment.balance, date: adjustment.date,
                createdAt: adjustment.createdAt, id: adjustment.id.uuidString
            )
            if (candidate.date, candidate.createdAt, candidate.id) > (latest.date, latest.createdAt, latest.id) {
                latest = candidate
            }
        }
        return latest
    }

    /// Whether an entry dated `date` and logged at `createdAt` comes after
    /// a checkpoint stated at `checkpoint` (and is dated by `asOf`'s day).
    private static func counts(date: Date, createdAt: Date, after checkpoint: Date, asOf: Date?, calendar: Calendar) -> Bool {
        if let asOf, calendar.compare(date, to: asOf, toGranularity: .day) == .orderedDescending { return false }
        switch calendar.compare(date, to: checkpoint, toGranularity: .day) {
        case .orderedDescending: return true
        case .orderedSame: return createdAt > checkpoint
        case .orderedAscending: return false
        }
    }

    /// The saved rate for what arrived. A transfer saves the rate of what
    /// left: within one currency it is the same; between two, what arrived
    /// was worth what left, so its rate is amountOut x rate / amountIn.
    private static func savedRateIn(of transfer: Transfer, currencyIn: String, currencyOut: String) -> ExchangeRate? {
        guard let rate = transfer.rate, rate.isUsable else { return nil }
        if CurrencyConverter.same(currencyIn, currencyOut) { return rate }
        guard transfer.amountIn > 0 else { return nil }
        var arrived = rate
        arrived.rate = transfer.amountOut * rate.rate / transfer.amountIn
        return arrived
    }
}
