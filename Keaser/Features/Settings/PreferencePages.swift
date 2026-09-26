import AppIntents
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
        .settingsListStyle(topMargin: 12)
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
        let isOn = Binding(
            get: { store.preferences.smartSuggestionsEnabled },
            set: { value in store.updatePreferences { $0.smartSuggestionsEnabled = value } }
        )
        List {
            Section {
                Toggle("Smart Suggestions", isOn: isOn)
                    .font(.body)
                    .foregroundStyle(.white)
                    // The app tints everything white, which would turn the
                    // switch into white on white; keep the system green.
                    .tint(Color(uiColor: .systemGreen))
                    .frame(minHeight: 52)
                    .cardRow(.single, insets: .settingsTextRow)
            } footer: {
                SettingsFootnote("""
                As you type a title in New Expense or Edit Expense, Keaser offers expenses you have logged before \
                that match it. Pick one to fill in the title, amount, category and payment method in a single tap, \
                then change anything you like before saving. For a title you haven't used yet, Keaser picks a likely \
                category and payment method when you move on from the title, and never replaces one you chose. \
                Suggestions are worked out on this iPhone from your own history, so they get more useful the more \
                you log. Turn this off to always start from an empty form.
                """)
            }
        }
        .settingsListStyle()
        .settingsPage("Smart Suggestions")
    }
}

/// How to reach Keaser's Add Expense action from outside the app.
struct ShortcutSettingsView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    SettingsSymbol(symbol: "command", size: 72, pointSize: 32)
                        .background(Color.settingsCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Text("Add Expense Shortcut")
                        .keaserFont(22, weight: .bold, relativeTo: .title2)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Keaser adds an \u{201C}\(Tutorials.addExpenseActionTitle)\u{201D} action to the Shortcuts app, so you can log a purchase without opening Keaser first.")
                        .font(.subheadline)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .plainListRow()
            }

            Section {
                SettingsSectionTitle("Run It From")
                let places = ShortcutPlace.allCases
                ForEach(Array(places.enumerated()), id: \.element) { index, place in
                    InfoRow(symbol: place.symbol, title: place.title, detail: place.detail)
                        .cardRow(CardPosition(index: index, count: places.count))
                }
            }

            Section {
                NavigationLink(value: SettingsPage.tutorial(.addExpenseShortcut)) {
                    SettingsRow(symbol: "book.pages", title: "Step-by-Step Tutorial")
                }
                .cardRow(.single)
            }
        }
        .settingsListStyle(sectionSpacing: 14, topMargin: 24)
        .settingsPage("Shortcut")
    }

    private enum ShortcutPlace: CaseIterable {
        case siri, actionButton, controlCenter, homeScreen, backTap

        var symbol: String {
            switch self {
            case .siri: "mic.fill"
            case .actionButton: "button.horizontal.top.press.fill"
            case .controlCenter: "switch.2"
            case .homeScreen: "apps.iphone"
            case .backTap: "hand.tap.fill"
            }
        }

        var title: String {
            switch self {
            case .siri: "Siri"
            case .actionButton: "Action Button"
            case .controlCenter: "Control Center"
            case .homeScreen: "Home Screen"
            case .backTap: "Back Tap"
            }
        }

        var detail: String {
            switch self {
            case .siri: "Say the name of your shortcut."
            case .actionButton: "Settings > Action Button > Shortcut."
            case .controlCenter: "Add a Shortcut control and pick yours."
            case .homeScreen: "Share the shortcut > Add to Home Screen."
            case .backTap: "Settings > Accessibility > Touch > Back Tap."
            }
        }
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
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isChecked {
                Image(systemName: "checkmark")
                    .keaserFont(17, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
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
                    .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
            .foregroundStyle(.white)
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(.body)
            .foregroundStyle(Color.keaserSecondaryText)
    }
}
