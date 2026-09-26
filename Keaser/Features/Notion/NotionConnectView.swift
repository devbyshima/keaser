import KeaserKit
import SwiftUI

/// The "Connect to Notion" flow, presented as a sheet from Add Account.
/// Calls `onFinish` with the new account's ID, or nil if cancelled.
///
/// Keaser has no server for Notion's OAuth, so the person creates an
/// internal connection in Notion, pastes its token here and shares a
/// database with it. Steps: intro (token), choose a database (or create
/// one), review the property mapping, connect.
struct NotionConnectView: View {
    var onFinish: (UUID?) -> Void

    @State private var model = NotionConnectModel()
    @State private var didFinish = false
    @Environment(KeaserStore.self) private var store

    var body: some View {
        content
            .interactiveDismissDisabled(model.isBusy)
            .keaserSheetChrome()
            // Swiping the sheet away counts as cancelling.
            .onDisappear { finish(nil) }
    }

    private func finish(_ accountID: UUID?) {
        guard !didFinish else { return }
        didFinish = true
        onFinish(accountID)
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if DebugLaunch.string("KeaserNotionStep") == "section" {
            NotionAccountSectionPreviewHost()
        } else {
            flow
        }
        #else
        flow
        #endif
    }

    private var flow: some View {
        NavigationStack(path: $model.path) {
            NotionIntroStep(model: model) { finish(nil) }
                .navigationDestination(for: NotionConnectModel.Step.self) { step in
                    switch step {
                    case .databases: NotionDatabasesStep(model: model)
                    case .newDatabase: NotionNewDatabaseStep(model: model)
                    case .review: NotionReviewStep(model: model, onFinish: finish)
                    }
                }
        }
        #if DEBUG
        .task {
            if let step = DebugLaunch.string("KeaserNotionStep") {
                await model.openDebugStep(step, currencyCode: store.preferences.currencyCode)
            }
        }
        #endif
    }
}

// MARK: - Intro

private struct NotionIntroStep: View {
    @Bindable var model: NotionConnectModel
    var onClose: () -> Void
    @FocusState private var tokenFocused: Bool

    private static let tokenFieldID = "token"

    var body: some View {
        VStack(spacing: 0) {
            KeaserSheetHeader(title: "Connect to Notion") {
                KeaserCircleButton("xmark", label: "Close", action: onClose)
            }
            .notionHeaderPadding()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        hero
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                        steps
                        tokenField
                            .padding(.top, 24)
                            .id(Self.tokenFieldID)
                    }
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: model.tokenError) { _, error in
                    // At large text sizes the field may be scrolled away.
                    guard error != nil else { return }
                    withAnimation { proxy.scrollTo(Self.tokenFieldID, anchor: .bottom) }
                }
            }
        }
        .keaserBottomBar {
            // A refused token is explained under the field, not here, where
            // it would push the bar up over the page.
            NotionPrimaryButton(
                title: "Continue",
                isWorking: model.isValidating,
                isEnabled: !model.trimmedToken.isEmpty
            ) {
                tokenFocused = false
                Task { await model.validateToken() }
            }
        }
        .notionPageBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var hero: some View {
        VStack(spacing: 16) {
            // The two marks as onboarding draws them: the Keaser tile a
            // little smaller than the outlined Notion tile, which reads
            // larger for its border.
            HStack(spacing: 14) {
                KeaserLogo(size: 58)
                    .frame(width: 64, height: 64)
                // Fixed like the 64pt tiles either side of it; the row is
                // an illustration, hidden from VoiceOver.
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.keaserSecondaryText)
                NotionMark(size: 64, style: .outlined)
            }
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Sync with Notion")
                    .font(.keaserTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Expenses you add or change in Keaser or in Notion show up in both.")
                    .font(.subheadline)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
        }
    }

    private var steps: some View {
        KeaserCard {
            NotionStepRow(
                number: 1,
                title: "Create a connection",
                detail: "At [notion.so/my-integrations](https://www.notion.so/my-integrations), make an internal connection.",
                hasLink: true
            )
            NotionStepRow(
                number: 2,
                title: "Copy its token",
                detail: "Copy the access token from its Configuration tab.",
                separated: true
            )
            NotionStepRow(
                number: 3,
                title: "Share a database",
                detail: "In your database, tap ••• then Connections and add it.",
                separated: true
            )
        }
        .padding(.horizontal, 16)
    }

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Access token")
                .font(.headline)
                .foregroundStyle(Color.keaserSecondaryText)
                .padding(.horizontal, 32)
                .accessibilityHidden(true)
            SecureField("Paste your token", text: $model.token)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($tokenFocused)
                .submitLabel(.continue)
                .onSubmit { Task { await model.validateToken() } }
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(minHeight: 50)
                .background(Color.keaserSheetCard, in: Capsule())
                .padding(.horizontal, 16)
                .accessibilityLabel("Access token")
            ZStack(alignment: .topLeading) {
                if let error = model.tokenError {
                    NotionErrorText(message: error)
                } else {
                    Text("Kept in your Keychain and only ever sent to Notion.")
                        .font(.footnote)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: model.tokenError)
        }
    }
}

/// One numbered step of the intro card.
private struct NotionStepRow: View {
    let number: Int
    let title: String
    /// Markdown, so the first step can link to Notion.
    let detail: LocalizedStringKey
    /// The detail holds a link. VoiceOver only offers it when the detail is
    /// an element of its own, so the step is not read as one.
    var hasLink = false
    var separated = false

    @ScaledMetric(relativeTo: .subheadline) private var badge: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            if separated {
                KeaserRowSeparator(leading: 16 + badge + 6 + 12)
            }
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: badge, height: badge)
                .background(Color.white.opacity(0.1), in: Circle())
                .frame(width: badge + 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Step \(number): \(title)")
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.keaserSecondaryText)
                    .tint(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: hasLink ? .contain : .combine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Databases

private struct NotionDatabasesStep: View {
    @Bindable var model: NotionConnectModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            KeaserSheetHeader(title: "Choose Database") {
                KeaserCircleButton("chevron.left", label: "Back") { dismiss() }
            }
            .notionHeaderPadding()
            ScrollView {
                VStack(spacing: 0) {
                    if let workspace = model.user?.workspaceName {
                        connectedBadge(workspace)
                            .padding(.bottom, 20)
                    }
                    if model.isLoadingSources && model.dataSources.isEmpty {
                        loading
                    } else if let error = model.sourcesError, model.dataSources.isEmpty {
                        EmptyStateView(symbol: "exclamationmark.triangle", title: "Couldn't Load", message: error) {
                            retryButton
                        }
                        .padding(.top, 80)
                    } else {
                        list
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .refreshable { await model.loadDataSources() }
        }
        .notionPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if !model.hasLoadedSources { await model.loadDataSources() }
        }
    }

    private func connectedBadge(_ workspace: String) -> some View {
        Label {
            Text("Connected to \(workspace)")
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // A capsule on one line; a rounded card, not a pill with the icon
        // outside it, when a large text size wraps the name.
        .background(Color.keaserSheetCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Wrapped, it lines up with the cards below instead of running to
        // the sheet's edges.
        .padding(.horizontal, 16)
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Looking for databases…")
                .font(.subheadline)
                .foregroundStyle(Color.keaserSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var retryButton: some View {
        Button("Try Again") { Task { await model.loadDataSources() } }
            .font(.body.weight(.semibold))
            .keaserGlassButtonStyle()
    }

    @ViewBuilder
    private var list: some View {
        if model.dataSources.isEmpty {
            EmptyStateView(
                symbol: "tablecells",
                title: "No Databases",
                message: "Share a database with your connection in Notion (••• then Connections), then pull down to refresh."
            )
            .padding(.top, 40)
            .padding(.bottom, 32)
        } else {
            NotionSectionTitle(text: "Shared with Keaser")
            KeaserCard {
                ForEach(Array(model.dataSources.enumerated()), id: \.element.id) { index, source in
                    Button {
                        model.choose(source)
                    } label: {
                        NotionRow(title: source.displayTitle, subtitle: model.matchSummary(for: source), separated: index > 0) {
                            NotionEmojiTile(emoji: source.iconEmoji)
                        } trailing: {
                            NotionChevron()
                        }
                    }
                    .buttonStyle(HighlightRowButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }

        KeaserCard {
            Button {
                model.path.append(.newDatabase)
            } label: {
                NotionRow(title: "New Keaser Database", subtitle: "Created in a page you choose") {
                    NotionRowSymbol(symbol: "plus.circle.fill")
                } trailing: {
                    NotionChevron()
                }
            }
            .buttonStyle(HighlightRowButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        NotionFootnote(text: "Don't see your database? In Notion, open it, tap ••• then Connections and add your connection. Then pull down to refresh.")
    }
}

// MARK: - New database

private struct NotionNewDatabaseStep: View {
    @Bindable var model: NotionConnectModel
    @Environment(\.dismiss) private var dismiss
    @Environment(KeaserStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            KeaserSheetHeader(title: "New Database") {
                KeaserCircleButton("chevron.left", label: "Back") { dismiss() }
            }
            .notionHeaderPadding()
            ScrollView {
                VStack(spacing: 0) {
                    Text("Keaser will create “\(NotionConnectModel.newDatabaseTitle)” with Name, Amount, Category, Payment, Date and Keaser ID properties. Choose the page it goes in.")
                        .font(.subheadline)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                    if model.isLoadingPages && model.pages.isEmpty {
                        ProgressView().tint(.white).padding(.top, 60)
                    } else if model.pages.isEmpty {
                        EmptyStateView(
                            symbol: "doc.text",
                            title: "No Pages",
                            message: model.pagesError ?? "Share a page with your connection in Notion (••• then Connections), then pull down to refresh."
                        )
                        .padding(.top, 40)
                    } else {
                        pageList
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .refreshable { await model.loadPages() }
        }
        .notionPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model.pages.isEmpty { await model.loadPages() }
        }
    }

    @ViewBuilder
    private var pageList: some View {
        NotionSectionTitle(text: "Shared pages")
        KeaserCard {
            ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                Button {
                    Task { await model.createDatabase(in: page, currencyCode: store.preferences.currencyCode) }
                } label: {
                    NotionRow(title: page.displayTitle, separated: index > 0) {
                        NotionEmojiTile(emoji: page.iconEmoji, fallback: "doc.text")
                    } trailing: {
                        if model.creatingInPageID == page.id {
                            ProgressView().tint(.white)
                        } else {
                            NotionChevron()
                        }
                    }
                }
                .buttonStyle(HighlightRowButtonStyle())
                .disabled(model.creatingInPageID != nil)
            }
        }
        .padding(.horizontal, 16)
        if let error = model.pagesError {
            NotionErrorText(message: error).padding(.top, 12)
        }
    }
}

// MARK: - Review

private struct NotionReviewStep: View {
    @Bindable var model: NotionConnectModel
    var onFinish: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            KeaserSheetHeader(title: "Review") {
                // Linked already: there is nothing to go back to.
                if model.connectedAccountID == nil {
                    KeaserCircleButton("chevron.left", label: "Back") { dismiss() }
                }
            }
            .notionHeaderPadding()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    nameField
                    if let source = model.selected {
                        NotionSectionTitle(text: "Database")
                            .padding(.top, 28)
                        KeaserCard {
                            NotionRow(title: source.displayTitle, subtitle: model.user?.workspaceName ?? "Notion") {
                                NotionEmojiTile(emoji: source.iconEmoji)
                            } trailing: {
                                NotionMark(size: 24, style: .outlined)
                            }
                        }
                        .padding(.horizontal, 16)
                        properties
                            .padding(.top, 28)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .keaserBottomBar {
            NotionPrimaryButton(
                title: model.connectedAccountID == nil ? "Connect" : "Done",
                isWorking: model.isConnecting,
                isEnabled: model.canConnect || model.connectedAccountID != nil,
                error: model.connectError
            ) {
                nameFocused = false
                Task {
                    if let id = await model.connect() { onFinish(id) }
                }
            }
        }
        .notionPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .disabled(model.isConnecting)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account name")
                .font(.headline)
                .foregroundStyle(Color.keaserSecondaryText)
                .padding(.horizontal, 32)
                .accessibilityHidden(true)
            TextField("e.g. Personal", text: $model.accountName)
                .focused($nameFocused)
                .submitLabel(.done)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(minHeight: 50)
                .background(Color.keaserSheetCard, in: Capsule())
                .padding(.horizontal, 16)
                .accessibilityLabel("Account name")
        }
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: 0) {
            NotionSectionTitle(text: "Properties")
            KeaserCard {
                ForEach(Array(NotionExpenseField.allCases.enumerated()), id: \.element) { index, field in
                    NotionPropertyPickerRow(model: model, field: field, separated: index > 0)
                }
            }
            .padding(.horizontal, 16)
            NotionFootnote(text: "Keaser reads and writes only these properties, plus a Keaser ID it adds to match rows to expenses. Everything else in the database is left as it is.")
        }
    }
}

/// A review row: the expense field, and the Notion property it maps to.
private struct NotionPropertyPickerRow: View {
    let model: NotionConnectModel
    let field: NotionExpenseField
    var separated = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let current = model.property(for: field)
        NotionRow(title: field.displayName, separated: separated, hasControl: field != .title, trailingIsValue: true) {
            NotionRowSymbol(symbol: field.symbol)
        } trailing: {
            if field == .title {
                valueLabel(current?.name ?? "Name", showsChevrons: false)
            } else {
                Menu {
                    Picker(field.displayName, selection: Binding(
                        get: { current?.id },
                        set: { id in
                            model.setProperty(model.candidates(for: field).first { $0.id == id }, for: field)
                        }
                    )) {
                        Text("None").tag(String?.none)
                        ForEach(model.candidates(for: field)) { property in
                            Text("\(property.name) (\(property.type.displayName))").tag(String?.some(property.id))
                        }
                    }
                } label: {
                    valueLabel(current?.name ?? "None", showsChevrons: true)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                // The row's title is hidden; the menu says which field it sets.
                .accessibilityLabel(field.displayName)
                .accessibilityValue(current?.name ?? "None")
            }
        }
    }

    private func valueLabel(_ text: String, showsChevrons: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            if showsChevrons {
                Image(systemName: "chevron.up.chevron.down")
                    .keaserFont(13, weight: .semibold)
                    .accessibilityHidden(true)
            }
        }
        .font(.body)
        .foregroundStyle(Color.keaserSecondaryText)
    }
}
