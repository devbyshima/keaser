import Foundation

/// Names and versions every copy of Keaser syncing through the same iCloud
/// database must agree on. Changing one strands the data already in iCloud,
/// so they are only ever added to.
///
/// iCloud sync (see AGENTS.md, "iCloud sync") keeps every record in one
/// custom zone of the person's private CloudKit database. A record is one
/// account's details, one category, payment method or expense, the shared
/// settings, or one list order. Its content is a single encrypted field,
/// `payload`: the JSON of a `SyncRecord` envelope (see `SyncRecord`).
public enum SyncSchema {
    /// The iCloud container. Automatic signing creates it the first time
    /// the app is built with `Keaser/App/KeaserCloud.entitlements` under the
    /// paid Apple Developer Program.
    public static let containerIdentifier = "iCloud.com.fulltimestudio.keaser"

    /// The custom zone in the private database that holds every record.
    public static let zoneName = "Keaser"

    /// The encrypted CKRecord field holding a record's payload.
    public static let payloadField = "payload"

    /// The highest `SyncRecord.readerVersion` this build can apply. A later
    /// version that changes what an existing field means (not merely adds
    /// fields, which older builds keep untouched) raises the version it
    /// writes; older builds then park those records until they are updated,
    /// instead of misreading them.
    public static let readerVersion = 1
}
