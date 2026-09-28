import KeaserKit
import SwiftUI

/// Every ISO currency, searchable, with the current one checked. Picking one
/// goes straight back to Settings, as in the reference.
struct CurrencyPickerView: View {
    @Environment(KeaserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var options: [CurrencyOption] = []

    var body: some View {
        let current = store.preferences.currencyCode
        let results = CurrencyCatalog.filter(options, matching: query)
        List {
            Section {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, option in
                    Button {
                        store.updatePreferences { $0.currencyCode = option.code }
                        dismiss()
                    } label: {
                        CheckRow(title: option.title, isChecked: option.code == current)
                    }
                    .cardRow(CardPosition(index: index, count: results.count), insets: .settingsTextRow)
                }
            }
        }
        // The reference leaves the same gap under the search field as other
        // pages leave under the navigation bar.
        .settingsListStyle()
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .autocorrectionDisabled()
        .overlay {
            if results.isEmpty && !options.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .settingsPage("Currency")
        .onAppear {
            // Built once: ~300 localized names are not free to look up, and
            // the list must not reshuffle while the user scrolls.
            if options.isEmpty {
                options = CurrencyCatalog.options(including: [store.preferences.currencyCode])
            }
        }
    }
}

/// Sunday or Monday. Week totals, charts and widgets follow this. Picking
/// one goes straight back to Settings, as in the reference.
struct StartWeekView: View {
    @Environment(KeaserStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let selected = store.preferences.firstWeekday
        List {
            Section {
                ForEach(Array(Weekday.allCases.enumerated()), id: \.element) { index, day in
                    Button {
                        store.updatePreferences { $0.firstWeekday = day }
                        dismiss()
                    } label: {
                        CheckRow(title: day.title, isChecked: day == selected)
                    }
                    .cardRow(CardPosition(index: index, count: Weekday.allCases.count), insets: .settingsTextRow)
                }
            }
        }
        .settingsListStyle()
        .settingsPage("Start Week On")
    }
}

/// The Smart Suggestions switch and what it does.
struct SmartSuggestionsView: View {
    @Environment(KeaserStore.self) private var store

    var body: some View {
        List {
            Section {
                SettingsToggle("Smart Suggestions", isOn: store.preferenceBinding(\.smartSuggestionsEnabled))
            } footer: {
                // The Apple Intelligence sentence only on iPhones that can
                // run it.
                SettingsFootnote(SmartSuggestionsCopy.footnote(mentionsAppleIntelligence: CategoryModels.isDeviceEligible))
            }
        }
        .settingsListStyle()
        .settingsPage("Smart Suggestions")
    }
}

/// How the Add Expense shortcut behaves: three switches, each with what it
/// does, as in the reference.
struct ShortcutSettingsView: View {
    @Environment(KeaserStore.self) private var store

    var body: some View {
        List {
            Section {
                SettingsToggle("Confirm Expense Details", isOn: store.preferenceBinding(\.shortcutConfirmsDetails))
            } footer: {
                SettingsFootnote("""
                When enabled, Keaser asks for confirmation before creating an expense from the shortcut. \
                When disabled, the expense is created immediately without confirmation.
                """)
            }
            Section {
                SettingsToggle("Enable Go Back Option", isOn: store.preferenceBinding(\.shortcutGoBackEnabled))
            } footer: {
                SettingsFootnote("""
                Show a Go Back option while selecting account, category, or payment in shortcut so you can \
                return to the previous step.
                """)
            }
            Section {
                SettingsToggle("Smart Suggestions", isOn: store.preferenceBinding(\.shortcutSmartSuggestionsEnabled))
            } footer: {
                SettingsFootnote("""
                When enabled, Keaser intelligently suggests a category and payment method based on the expense \
                title. Over time, Keaser learns from your past expenses, making suggestions more accurate and helpful.
                """)
            }
        }
        // Each footnote sits 22pt above the next card, as in the reference.
        .settingsListStyle(sectionSpacing: 17.5)
        .settingsPage("Shortcut")
    }
}

/// A switch alone in a card, with the system green: the app's ink tint
/// would turn it white on white in dark mode.
struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .font(.body)
            .foregroundStyle(Color.keaserPrimaryText)
            .tint(Color(uiColor: .systemGreen))
            .frame(minHeight: 52)
            .cardRow(.single, insets: .settingsTextRow)
    }
}

extension KeaserStore {
    /// A switch's binding to one preference, saved as it changes.
    func preferenceBinding(_ keyPath: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.preferences[keyPath: keyPath] },
            set: { value in self.updatePreferences { $0[keyPath: keyPath] = value } }
        )
    }
}

/// A plain title with a checkmark when selected (currency, week start).
struct CheckRow: View {
    let title: String
    let isChecked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isChecked {
                Image(systemName: "checkmark")
                    .keaserFont(17, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .accessibilityHidden(true)
            }
        }
        // A one-line row is the 52pt minimum; a name that wraps gets the
        // reference's 15pt above and below.
        .padding(.vertical, 15)
        .frame(minHeight: 52)
        .cardSeparatorTrailing()
        .contentShape(Rectangle())
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

/// Symbol, title and a line of explanation; not tappable.
struct InfoRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 13) {
            SettingsSymbol(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.keaserPrimaryText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .cardSeparatorTrailing()
        .accessibilityElement(children: .combine)
    }
}

/// A 52pt row with a bare symbol (no tile), as on the Tutorials, Help and
/// Follow Us pages. At accessibility sizes the value moves under the title.
struct CompactRow: View {
    let symbol: String
    let title: String
    var value: String?
    var accessory: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var symbolWidth: CGFloat = 24

    init(symbol: String, title: String, value: String? = nil, accessory: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.value = value
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .keaserFont(19, weight: .medium, relativeTo: .body)
                .foregroundStyle(Color.keaserPrimaryText)
                .frame(width: symbolWidth)
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    if let value { valueText(value) }
                }
                .padding(.vertical, 10)
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
            } else {
                titleText
                    .lineLimit(1)
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
                if let value {
                    valueText(value)
                        .lineLimit(1)
                }
            }
            if let accessory {
                Image(systemName: accessory)
                    .keaserFont(13, weight: .semibold, relativeTo: .footnote)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 52)
        .cardSeparatorTrailing()
        .contentShape(Rectangle())
    }

    private var titleText: some View {
        Text(title)
            .font(.body)
            .foregroundStyle(Color.keaserPrimaryText)
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(.body)
            .foregroundStyle(Color.keaserSecondaryText)
    }
}
