import Foundation

/// The words under the switch on Settings > Smart Suggestions.
public enum SmartSuggestionsCopy {
    /// What the switch does, as the reference words it.
    public static let summary = "When enabled, Keaser suggests matching past expenses as you type the expense title "
        + "in the Create and Edit screens. Selecting a suggestion can instantly prefill details such as the title, "
        + "amount, category, and payment method. If no match is found, Keaser intelligently suggests a category and "
        + "payment method based on the expense title. Over time, Keaser learns from your past expenses, making "
        + "suggestions more accurate and helpful."

    /// What the on-device model adds, for iPhones that can run Apple
    /// Intelligence.
    public static let appleIntelligence = "With Apple Intelligence turned on, Keaser also recognizes titles it has "
        + "never seen, such as shop and brand names, right on this iPhone."

    /// The footnote: the summary, then the Apple Intelligence sentence
    /// when `mentionsAppleIntelligence`.
    public static func footnote(mentionsAppleIntelligence: Bool) -> String {
        mentionsAppleIntelligence ? summary + " " + appleIntelligence : summary
    }
}
