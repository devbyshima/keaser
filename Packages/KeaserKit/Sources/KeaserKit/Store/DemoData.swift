import Foundation

/// Deterministic sample data for previews, screenshots and debug launches.
/// Dates are relative to `now` so "this month" always has something in it;
/// amounts and titles come from a fixed-seed generator so two runs match.
public enum DemoData {
    public enum Seed: String, CaseIterable, Sendable {
        /// First launch: onboarding not done, no accounts.
        case fresh
        /// Onboarding done, welcome letter seen, no accounts yet.
        case onboarded
        /// One empty "Personal" account.
        case account
        /// One account with the single "Outing" expense from the reference
        /// recording.
        case single
        /// Two accounts, "Personal" full of expenses across three years.
        case demo
    }

    public static func database(_ seed: Seed, now: Date = .now, calendar: Calendar = .current) -> Database {
        var prefs = Preferences(currencyCode: "USD", firstWeekday: .sunday)
        switch seed {
        case .fresh:
            return Database(preferences: prefs)
        case .onboarded:
            prefs.hasCompletedOnboarding = true
            prefs.hasSeenWelcomeLetter = true
            prefs.trialStartDate = now
            return Database(preferences: prefs)
        case .account:
            prefs.hasCompletedOnboarding = true
            prefs.hasSeenWelcomeLetter = true
            prefs.trialStartDate = now
            let account = Account(name: "Personal", createdAt: now)
            prefs.selectedAccountID = account.id
            return Database(accounts: [account], preferences: prefs)
        case .single:
            prefs.hasCompletedOnboarding = true
            prefs.hasSeenWelcomeLetter = true
            prefs.trialStartDate = now
            var account = Account(name: "Personal", createdAt: now)
            let food = account.categories.first { $0.name == "Food & Drinks" }
            let debit = account.paymentMethods.first { $0.name == "Debit Card" }
            account.expenses = [
                Expense(title: "Outing", amount: 20, categoryID: food?.id, paymentMethodID: debit?.id, date: now, createdAt: now, updatedAt: now),
            ]
            prefs.selectedAccountID = account.id
            return Database(accounts: [account], preferences: prefs)
        case .demo:
            prefs.hasCompletedOnboarding = true
            prefs.hasSeenWelcomeLetter = true
            prefs.trialStartDate = now
            var personal = Account(name: "Personal", createdAt: now)
            personal.expenses = generateExpenses(for: personal, now: now, calendar: calendar)
            let business = Account(name: "Business", createdAt: now)
            prefs.selectedAccountID = personal.id
            return Database(accounts: [personal, business], preferences: prefs)
        }
    }

    private static let templates: [(title: String, category: String, low: Int, high: Int)] = [
        ("Coffee", "Food & Drinks", 3, 7),
        ("Groceries", "Shopping", 25, 120),
        ("Gas", "Transportation", 30, 70),
        ("Lunch", "Food & Drinks", 9, 25),
        ("Dinner out", "Food & Drinks", 25, 90),
        ("Uber", "Transportation", 8, 35),
        ("Netflix", "Entertainment", 15, 16),
        ("Movie tickets", "Entertainment", 12, 40),
        ("Pharmacy", "Health", 6, 45),
        ("Gym membership", "Health", 30, 60),
        ("Haircut", "Services", 20, 45),
        ("Phone bill", "Services", 35, 65),
        ("Flight", "Travel", 120, 480),
        ("Hotel", "Travel", 90, 260),
        ("New shoes", "Shopping", 45, 140),
    ]

    private static func generateExpenses(for account: Account, now: Date, calendar: Calendar) -> [Expense] {
        var rng = SplitMix64(seed: 0x4B45_4153_4552) // "KEASER"
        var result: [Expense] = []
        let today = calendar.startOfDay(for: now)
        // Denser recently, sparser further back, over ~3 years.
        for dayOffset in 0..<(365 * 3) {
            let chance = dayOffset < 45 ? 70 : (dayOffset < 365 ? 35 : 15)
            guard Int(rng.next() % 100) < chance,
                  let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)
            else { continue }
            let count = 1 + Int(rng.next() % 2)
            for _ in 0..<count {
                let template = templates[Int(rng.next() % UInt64(templates.count))]
                let span = UInt64(template.high - template.low + 1)
                let whole = template.low + Int(rng.next() % span)
                let cents = Int(rng.next() % 100)
                let amount = Decimal(whole) + Decimal(cents) / 100
                let category = account.categories.first { $0.name == template.category }
                let method = account.paymentMethods[Int(rng.next() % UInt64(account.paymentMethods.count))]
                let created = day.addingTimeInterval(Double(rng.next() % 50_000) + 25_000)
                result.append(Expense(
                    title: template.title,
                    amount: amount,
                    categoryID: category?.id,
                    paymentMethodID: method.id,
                    date: day,
                    createdAt: created,
                    updatedAt: created
                ))
            }
        }
        return result
    }
}

/// Small, fast, seedable PRNG so demo data is identical on every run.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
