import KeaserKit
import SwiftUI

/// Home's floating bar: the account switcher on the left and one glass
/// capsule with search, filters and settings on the right. While searching it
/// becomes a search field with a Cancel button.
struct HomeTopBar<FilterMenu: View>: View {
    let accountName: String
    let isSearching: Bool
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    let onAccounts: () -> Void
    let onSearch: () -> Void
    let onCancelSearch: () -> Void
    let onSettings: () -> Void
    @ViewBuilder var filterMenu: FilterMenu

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        KeaserGlassContainer(spacing: 12) {
            HStack(spacing: 10) {
                if isSearching {
                    searchField
                        .transition(slide(from: .trailing))
                    cancelButton
                        .transition(slide(from: .trailing))
                } else {
                    accountButton
                        .transition(slide(from: .leading))
                    Spacer(minLength: 0)
                    tools
                        .transition(slide(from: .trailing))
                }
            }
        }
        .frame(minHeight: HomeLayout.topBarHeight)
        .padding(.horizontal, KeaserMetrics.screenPadding)
        .background(alignment: .top) {
            // Content scrolling under the bar fades out instead of clashing
            // with the glass, like the system's scroll edge effect.
            LinearGradient(colors: [.black, .black.opacity(0.85), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .padding(.bottom, -18)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    /// Controls slide in from their edge, or only fade with Reduce Motion.
    private func slide(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    // Like a system toolbar, the bar's text stops growing at the largest
    // standard size (it has to stay one row tall); the Large Content Viewer
    // shows each control bigger at accessibility sizes. The cap is applied to
    // the labels only, so the buttons still see the real text size.

    private var accountButton: some View {
        Button(action: onAccounts) {
            HStack(spacing: 5) {
                Text(accountName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Color.keaserPrimaryText)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, 17)
            .frame(minHeight: HomeLayout.topBarHeight)
            .frame(maxWidth: 210, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Capsule())
            .keaserGlass(interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account: \(accountName)")
        .accessibilityHint("Switch or manage accounts")
        .accessibilityShowsLargeContentViewer {
            Label(accountName, systemImage: "chevron.up.chevron.down")
        }
    }

    private var tools: some View {
        HStack(spacing: 0) {
            Button(action: onSearch) {
                HomeToolIcon(symbol: "magnifyingglass")
            }
            .accessibilityLabel("Search")
            .accessibilityShowsLargeContentViewer {
                Label("Search", systemImage: "magnifyingglass")
            }
            filterMenu
            Button(action: onSettings) {
                HomeToolIcon(symbol: "gear")
            }
            .accessibilityLabel("Settings")
            .accessibilityShowsLargeContentViewer {
                Label("Settings", systemImage: "gear")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 0.5)
        .keaserGlass(interactive: true)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.keaserSecondaryText)
                .accessibilityHidden(true)
            TextField("Search", text: $searchText, prompt: Text("Search").foregroundStyle(Color.keaserSecondaryText))
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
                .focused(searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Taps across 44pt but takes the drawn 28pt in the row.
                .padding(-8)
                .accessibilityLabel("Clear Search")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: HomeLayout.topBarHeight)
        .keaserGlass()
        .animation(.snappy(duration: 0.2), value: searchText.isEmpty)
    }

    private var cancelButton: some View {
        Button(action: onCancelSearch) {
            Text("Cancel")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.keaserPrimaryText)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.horizontal, 16)
                .frame(minHeight: HomeLayout.topBarHeight)
                .contentShape(Capsule())
                .keaserGlass(interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer()
    }
}

/// One icon in the top bar's tool capsule.
struct HomeToolIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .keaserFont(21, weight: .medium, relativeTo: .title3)
            .foregroundStyle(Color.keaserPrimaryText)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(width: 47)
            .frame(minHeight: HomeLayout.topBarHeight)
            .contentShape(Rectangle())
    }
}

/// The filter button: a native menu with Period, Category and Payment Method
/// submenus, each showing its current choice. Choices that need Pro carry a
/// lock and open the paywall instead (the caller decides).
struct HomeFilterMenu: View {
    let account: Account
    let period: Period
    let categoryID: UUID?
    let paymentMethodID: UUID?
    let isPro: Bool
    let onPeriod: @MainActor (Period) -> Void
    let onCategory: @MainActor (UUID?) -> Void
    let onPaymentMethod: @MainActor (UUID?) -> Void

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { period }, set: onPeriod)) {
                ForEach(Period.allCases) { option in
                    optionLabel(option.title, locked: option.isLongTerm && !isPro)
                        .tag(option)
                }
            } label: {
                Label("Period", systemImage: "calendar")
            }
            .pickerStyle(.menu)

            Picker(selection: Binding(get: { categoryID }, set: onCategory)) {
                Text("All").tag(UUID?.none)
                ForEach(ExpenseQuery.alphabetical(account.categories)) { category in
                    optionLabel(category.name, locked: !isPro)
                        .tag(UUID?.some(category.id))
                }
            } label: {
                Label("Category", systemImage: "tag")
            }
            .pickerStyle(.menu)

            Picker(selection: Binding(get: { paymentMethodID }, set: onPaymentMethod)) {
                Text("All").tag(UUID?.none)
                ForEach(ExpenseQuery.alphabetical(account.paymentMethods)) { method in
                    optionLabel(method.name, locked: !isPro)
                        .tag(UUID?.some(method.id))
                }
            } label: {
                Label("Payment Method", systemImage: "creditcard")
            }
            .pickerStyle(.menu)
        } label: {
            HomeToolIcon(symbol: isNarrowed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Filters")
        .accessibilityValue(accessibilitySummary)
        .accessibilityShowsLargeContentViewer {
            Label("Filters", systemImage: "line.3.horizontal.decrease")
        }
    }

    private var isNarrowed: Bool { categoryID != nil || paymentMethodID != nil }

    @ViewBuilder
    private func optionLabel(_ title: String, locked: Bool) -> some View {
        if locked {
            Label(title, systemImage: "lock.fill")
        } else {
            Text(title)
        }
    }

    private var accessibilitySummary: String {
        var parts = [period.title]
        if let name = account.category(id: categoryID)?.name { parts.append(name) }
        if let name = account.paymentMethod(id: paymentMethodID)?.name { parts.append(name) }
        return parts.joined(separator: ", ")
    }
}
