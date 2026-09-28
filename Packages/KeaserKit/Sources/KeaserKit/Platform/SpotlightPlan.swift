import Foundation

/// What Keaser keeps in the iPhone's on-device Spotlight index, and how an
/// index that is out of date is brought back in line.
///
/// The app remembers what it last wrote (a `SpotlightManifest`: every
/// expense and account ID with a fingerprint of what was indexed for it).
/// After any change it works out the manifest the database calls for and
/// writes only the difference, so a rename re-indexes that account's
/// expenses, a deleted account takes its expenses out, and a change missed
/// while the app was closed is caught on the next launch.
public enum SpotlightPlan {
    /// The named index Keaser writes to (Apple asks apps not to use the
    /// default index).
    public static let indexName = "com.fulltimestudio.keaser.entities"

    /// Bump whenever what goes into the index changes, so every copy of the
    /// app rebuilds its index on the next launch.
    public static let formatVersion = 1

    /// How many items go to Spotlight in one call.
    public static let batchSize = 200

    /// Names the app build and index format an index was written by, such
    /// as "1/1.0.0/1".
    public static func marker(appVersion: String, build: String, format: Int = formatVersion) -> String {
        "\(format)/\(appVersion)/\(build)"
    }

    /// The version marker rule: the whole index is rebuilt when it was
    /// written by another build or format of the app, or never written
    /// (the first launch after installing).
    public static func needsFullReindex(indexedMarker: String?, currentMarker: String) -> Bool {
        indexedMarker != currentMarker
    }

    /// What the index should hold for `database`: every expense and every
    /// account.
    public static func manifest(for database: Database, marker: String?) -> SpotlightManifest {
        var manifest = SpotlightManifest(marker: marker)
        for summary in EntityCatalog.allExpenses(in: database) {
            manifest.expenses[summary.id] = fingerprint(summary)
        }
        for account in database.accounts {
            manifest.accounts[account.id] = fingerprint(account)
        }
        return manifest
    }

    /// What to write to turn an index holding `indexed` into one holding
    /// `wanted`: new or changed items to index, gone ones to delete.
    public static func changes(from indexed: SpotlightManifest, to wanted: SpotlightManifest) -> SpotlightChanges {
        SpotlightChanges(
            expensesToIndex: changed(from: indexed.expenses, to: wanted.expenses),
            expensesToDelete: removed(from: indexed.expenses, in: wanted.expenses),
            accountsToIndex: changed(from: indexed.accounts, to: wanted.accounts),
            accountsToDelete: removed(from: indexed.accounts, in: wanted.accounts)
        )
    }

    /// `items` in runs of at most `size`, in order.
    public static func batches<Element>(_ items: [Element], size: Int = batchSize) -> [[Element]] {
        let size = max(1, size)
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0 ..< min($0 + size, items.count)]) }
    }

    /// The expense or account an item Spotlight hands back stands for: the
    /// last UUID in its identifier, whether that is the bare ID or the ID
    /// with the entity type in front.
    public static func entityID(inItemIdentifier identifier: String) -> UUID? {
        let length = 36
        let characters = Array(identifier)
        guard characters.count >= length else { return nil }
        for start in stride(from: characters.count - length, through: 0, by: -1) {
            if let id = UUID(uuidString: String(characters[start ..< start + length])) { return id }
        }
        return nil
    }

    // MARK: Fingerprints

    /// Changes whenever anything Spotlight shows or searches for this
    /// expense changes, including its account's and labels' names and the
    /// currency.
    public static func fingerprint(_ summary: ExpenseSummary) -> UInt64 {
        stableHash([
            summary.title,
            "\(summary.amount)",
            summary.currencyCode,
            "\(summary.date.timeIntervalSinceReferenceDate.bitPattern)",
            summary.categoryName ?? "",
            summary.paymentMethodName ?? "",
            summary.accountName,
            summary.symbol,
        ])
    }

    public static func fingerprint(_ account: Account) -> UInt64 {
        stableHash([account.name])
    }

    /// FNV-1a over the fields, separated by a unit separator. Unlike
    /// `Hasher`, it gives the same value in every launch, so the manifest
    /// can be kept on disk.
    static func stableHash(_ fields: [String]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for (index, field) in fields.enumerated() {
            if index > 0 {
                hash ^= 0x1F
                hash = hash &* 0x0000_0100_0000_01B3
            }
            for byte in field.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        return hash
    }

    private static func changed(from indexed: [UUID: UInt64], to wanted: [UUID: UInt64]) -> [UUID] {
        wanted.compactMap { id, print in indexed[id] == print ? nil : id }.sorted(by: uuidOrder)
    }

    private static func removed(from indexed: [UUID: UInt64], in wanted: [UUID: UInt64]) -> [UUID] {
        indexed.keys.filter { wanted[$0] == nil }.sorted(by: uuidOrder)
    }

    private static func uuidOrder(_ a: UUID, _ b: UUID) -> Bool {
        a.uuidString < b.uuidString
    }
}

/// What Keaser last wrote to its Spotlight index.
public struct SpotlightManifest: Codable, Hashable, Sendable {
    /// The build and format that wrote it (`SpotlightPlan.marker`); nil
    /// for an index never written.
    public var marker: String?
    public var expenses: [UUID: UInt64]
    public var accounts: [UUID: UInt64]

    public init(marker: String? = nil, expenses: [UUID: UInt64] = [:], accounts: [UUID: UInt64] = [:]) {
        self.marker = marker
        self.expenses = expenses
        self.accounts = accounts
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Nil for data that is not a manifest, which the caller treats as an
    /// index it knows nothing about (and rebuilds).
    public static func decoded(from data: Data) -> SpotlightManifest? {
        try? JSONDecoder().decode(SpotlightManifest.self, from: data)
    }
}

/// The difference between what the index holds and what it should hold.
/// Each list is sorted, so the same change always writes the same way.
public struct SpotlightChanges: Equatable, Sendable {
    public var expensesToIndex: [UUID]
    public var expensesToDelete: [UUID]
    public var accountsToIndex: [UUID]
    public var accountsToDelete: [UUID]

    public init(expensesToIndex: [UUID] = [], expensesToDelete: [UUID] = [], accountsToIndex: [UUID] = [], accountsToDelete: [UUID] = []) {
        self.expensesToIndex = expensesToIndex
        self.expensesToDelete = expensesToDelete
        self.accountsToIndex = accountsToIndex
        self.accountsToDelete = accountsToDelete
    }

    public var isEmpty: Bool {
        expensesToIndex.isEmpty && expensesToDelete.isEmpty && accountsToIndex.isEmpty && accountsToDelete.isEmpty
    }

    /// True when an account was added, renamed or removed, which is when
    /// Siri's "Open <account>" phrases need regenerating.
    public var touchesAccounts: Bool {
        !accountsToIndex.isEmpty || !accountsToDelete.isEmpty
    }
}
