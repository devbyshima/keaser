import KeaserKit
import SwiftUI

// Schematic drawings for the tutorials: small, calm stand-ins for the screens
// a step talks about, drawn in Keaser's monochrome palette. What the reader
// should tap is ringed in ink and marked with a touch point. Everything else
// stays grey, and text that does not matter to the step is a grey bar.

// The drawings' own colours, from the same values as the cards around them.
extension Color {
    /// A screen drawn inside an illustration card.
    fileprivate static let tutorialScreen = Color(light: .init(red: 242 / 255, green: 242 / 255, blue: 247 / 255), dark: .white.opacity(0.05))
    /// Rows, fields and controls on that screen.
    fileprivate static let tutorialCell = Color(light: .white, dark: .white.opacity(0.08))
    /// Stand-ins for text and icons the step does not need.
    fileprivate static let tutorialPlaceholder = Color(light: .black.opacity(0.08), dark: .white.opacity(0.12))
}

/// One illustration, sized to the reading column.
struct TutorialIllustrationView: View {
    let illustration: TutorialIllustration

    var body: some View {
        drawing
            // A drawing keeps one size: its text is part of the picture, and
            // the card hides it at the sizes where it would crowd the words.
            .dynamicTypeSize(.large)
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var drawing: some View {
        switch illustration {
        case .walletTrigger: WalletTriggerDrawing()
        case .walletOptions: WalletOptionsDrawing()
        case .walletVariables: WalletVariablesDrawing()
        case .currentDate: CurrentDateDrawing()
        case .askForCategory: AskForCategoryDrawing()
        }
    }
}

// MARK: - Drawings

/// The automation triggers, with Wallet picked out of the list.
private struct WalletTriggerDrawing: View {
    private let rows: [(symbol: String, title: String)] = [
        ("envelope.fill", "Email"),
        ("message.fill", "Message"),
        ("wallet.bifold.fill", "Wallet"),
        ("wave.3.right", "NFC"),
        ("square.grid.2x2.fill", "App"),
    ]

    var body: some View {
        Screen(padding: 10) {
            RowGroup {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Hairline(inset: 38) }
                    let isWallet = row.title == "Wallet"
                    MockRow(title: row.title, symbol: row.symbol, dim: !isWallet) { EmptyView() }
                        .ringed(isWallet)
                        .tapped(at: UnitPoint(x: 0.55, y: 0.55), isTapped: isWallet)
                }
            }
            // The list runs on above and below: it is scrolled to Wallet.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.28),
                        .init(color: .black, location: 0.72),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

/// The cards and categories that start the automation, and Run Immediately.
private struct WalletOptionsDrawing: View {
    var body: some View {
        Screen(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                RowGroup {
                    MockRow(title: "Debit Card", symbol: "creditcard.fill") { Check(isOn: true) }
                    Hairline(inset: 38)
                    MockRow(title: "Credit Card", symbol: "creditcard", dim: true) { Check(isOn: false) }
                }
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        CategoryChip(isOn: index < 2)
                    }
                    Spacer(minLength: 0)
                }
                RowGroup {
                    MockRow(title: "Run Immediately") { CheckGlyph() }
                        .ringed()
                        .tapped(at: UnitPoint(x: 0.55, y: 0.55))
                    Hairline(inset: 9)
                    MockRow(title: "Run After Confirmation", dim: true) { EmptyView() }
                }
            }
        }
    }

    /// A card's selection circle.
    private struct Check: View {
        let isOn: Bool

        var body: some View {
            if isOn {
                Image(systemName: "checkmark.circle.fill")
                    .keaserFont(15, weight: .semibold)
                    .foregroundStyle(Color.keaserInk)
            } else {
                Image(systemName: "circle")
                    .keaserFont(15)
                    .foregroundStyle(Color.keaserTertiaryText)
            }
        }
    }

    /// A purchase category, on or off.
    private struct CategoryChip: View {
        let isOn: Bool

        var body: some View {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark" : "plus")
                    .keaserFont(9, weight: .bold)
                    .foregroundStyle(isOn ? Color.keaserPrimaryText : Color.keaserTertiaryText)
                Capsule().fill(Color.tutorialPlaceholder).frame(width: 34, height: 6)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Color.tutorialCell, in: Capsule())
            .overlay {
                if isOn { Capsule().strokeBorder(Color.keaserInk.opacity(0.35), lineWidth: 1) }
            }
        }
    }
}

/// Title and Amount filled from the Shortcut Input: Merchant is in, and
/// Amount is being picked from the input's menu.
private struct WalletVariablesDrawing: View {
    var body: some View {
        Screen {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ActionBlock(expanded: false) {
                FieldRow(title: Tutorials.titleFieldTitle) {
                    VariableToken(symbol: "wallet.bifold.fill", title: "Merchant")
                }
                FieldRow(title: Tutorials.amountFieldTitle) {
                    VariableToken(symbol: "wallet.bifold.fill", title: "Amount")
                }
                .ringed()
            }
            Triangle()
                .fill(Color.tutorialCell)
                .frame(width: 16, height: 8)
                .padding(.trailing, 40)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "SHORTCUT INPUT")
                    .padding(.horizontal, 9)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                MockRow(title: "Amount") { CheckGlyph() }
                    .tapped(at: UnitPoint(x: 0.4, y: 0.55))
                Hairline(inset: 9)
                MockRow(title: "Merchant", dim: true) { EmptyView() }
                Hairline(inset: 9)
                MockRow(title: nil) { EmptyView() }
            }
            .frame(width: 190)
            .background(Color.tutorialCell, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.keaserSeparator, lineWidth: 0.5))
            .padding(.trailing, 8)
        }
    }
}

/// The Date field, with Current Date chosen above the keyboard.
private struct CurrentDateDrawing: View {
    var body: some View {
        Screen(padding: 10) {
            VStack(spacing: 10) {
                ActionBlock(expanded: true) {
                    FieldRow(title: Tutorials.accountFieldTitle) { EmptySlot() }
                    FieldRow(title: Tutorials.dateFieldTitle) {
                        VariableToken(symbol: "calendar", title: "Current Date")
                    }
                    .ringed()
                }
                // The bar scrolls sideways in Shortcuts, so a narrow screen
                // simply cuts it off at the edge.
                HStack(spacing: 6) {
                    OutlineToken(symbol: "wallet.bifold.fill", title: "Shortcut Input")
                    VariableToken(symbol: "calendar", title: "Current Date")
                        .tapped(at: UnitPoint(x: 0.6, y: 0.6))
                    OutlineToken(symbol: "doc.on.clipboard", title: "Clipboard")
                }
                .fixedSize()
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Cut sideways only, so the finger can reach below the bar.
                .mask { Rectangle().padding(.vertical, -30) }
                .background(Color.tutorialCell, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(spacing: 5) {
                    ForEach([10, 9, 7], id: \.self) { keys in
                        HStack(spacing: 5) {
                            ForEach(0..<keys, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.tutorialCell)
                                    .frame(height: 24)
                            }
                        }
                        .padding(.horizontal, CGFloat(10 - keys) * 9)
                    }
                }
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

/// Keaser asking for the one thing the shortcut left empty.
private struct AskForCategoryDrawing: View {
    var body: some View {
        let categories = Array(ExpenseCategory.defaults().filter { ["Food & Drinks", "Shopping", "Transportation"].contains($0.name) })
        Screen(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    KeaserAppIcon(size: 18)
                    Text("Keaser")
                        .keaserFont(11, weight: .semibold)
                        .foregroundStyle(Color.keaserSecondaryText)
                }
                .padding(.leading, 2)
                Text(Tutorials.categoryFieldTitle)
                    .keaserFont(15, weight: .bold)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .padding(.leading, 2)
                RowGroup {
                    ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                        if index > 0 { Hairline(inset: 38) }
                        MockRow(title: category.name, symbol: category.symbol, dim: index > 0) { EmptyView() }
                            .ringed(index == 0)
                            .tapped(at: UnitPoint(x: 0.55, y: 0.55), isTapped: index == 0)
                    }
                }
            }
        }
    }
}

// MARK: - Parts

/// A screen: the grey (or faintly lit) panel the rows sit on.
private struct Screen<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(Color.tutorialScreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Rows grouped on one rounded cell.
private struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.tutorialCell, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct Hairline: View {
    var inset: CGFloat

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.keaserSeparator)
            .frame(height: 1 / displayScale)
            .padding(.leading, inset)
    }
}

/// A list row: an optional symbol on a tile, a title (a grey bar when nil)
/// and whatever sits at its end.
private struct MockRow<Trailing: View>: View {
    let title: String?
    var symbol: String?
    var dim = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .keaserFont(10, weight: .semibold)
                    .foregroundStyle(dim ? Color.keaserSecondaryText : Color.keaserPrimaryText)
                    .frame(width: 21, height: 21)
                    .background(Color.tutorialPlaceholder, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if let title {
                Text(title)
                    .keaserFont(12.5, weight: dim ? .regular : .medium)
                    .foregroundStyle(dim ? Color.keaserSecondaryText : Color.keaserPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Capsule().fill(Color.tutorialPlaceholder).frame(width: 64, height: 7)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
    }
}

/// A small grey section title above a group.
private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .keaserFont(9.5, weight: .semibold)
            .tracking(0.3)
            .foregroundStyle(Color.keaserSecondaryText)
            .lineLimit(1)
            .padding(.leading, 3)
    }
}

/// Keaser's Add Expense action as the Shortcuts editor shows it, with its
/// fields underneath.
private struct ActionBlock<Fields: View>: View {
    let expanded: Bool
    @ViewBuilder var fields: Fields

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                KeaserAppIcon(size: 22)
                Text(Tutorials.addExpenseActionTitle)
                    .keaserFont(13, weight: .semibold)
                    .foregroundStyle(Color.keaserPrimaryText)
                Spacer(minLength: 4)
                Image(systemName: expanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .keaserFont(16)
                    .foregroundStyle(Color.keaserTertiaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            Hairline(inset: 0)
            VStack(spacing: 2) { fields }
                .padding(.vertical, 5)
        }
        .background(Color.tutorialCell, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

/// One field of the action: its name, then its value or an empty slot.
private struct FieldRow<Value: View>: View {
    let title: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .keaserFont(12, weight: .medium)
                .foregroundStyle(Color.keaserSecondaryText)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            value
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }
}

/// An empty field.
private struct EmptySlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.keaserTertiaryText, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            .frame(width: 64, height: 20)
    }
}

/// A variable in a field: an ink token, as Shortcuts draws variables in colour.
private struct VariableToken: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .keaserFont(9.5, weight: .bold)
            Text(title)
                .keaserFont(11.5, weight: .semibold)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Color.keaserOnInk)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Color.keaserInk, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// A variable on offer but not chosen.
private struct OutlineToken: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .keaserFont(9.5, weight: .semibold)
            Text(title)
                .keaserFont(11.5, weight: .medium)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Color.keaserSecondaryText)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Color.tutorialPlaceholder, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// A pointing finger, drawn like a pointer: ink with an outline in the
/// opposite colour, so it reads on light and dark parts of a drawing alike.
private struct TapMark: View {
    var body: some View {
        Image(systemName: "hand.point.up.left.fill")
            .keaserFont(17)
            .foregroundStyle(Color.keaserInk)
            .shadow(color: .keaserOnInk, radius: 0.5)
            .shadow(color: .keaserOnInk, radius: 0.5)
            .shadow(color: .keaserOnInk, radius: 0.5)
            .frame(width: 20, height: 20, alignment: .topLeading)
    }
}

/// The ink checkmark beside a chosen row.
private struct CheckGlyph: View {
    var body: some View {
        Image(systemName: "checkmark")
            .keaserFont(11, weight: .bold)
            .foregroundStyle(Color.keaserInk)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

extension View {
    /// Puts the tip of a pointing finger at `point` of this part of a
    /// drawing, above its neighbours.
    @ViewBuilder
    fileprivate func tapped(at point: UnitPoint, isTapped: Bool = true) -> some View {
        if isTapped {
            overlay {
                GeometryReader { proxy in
                    // The fingertip sits near the glyph's top leading corner.
                    TapMark()
                        .position(x: proxy.size.width * point.x + 8, y: proxy.size.height * point.y + 9)
                }
            }
            .zIndex(1)
        } else {
            self
        }
    }

    /// Rings a part of a drawing in ink: the thing to tap or set.
    fileprivate func ringed(_ isRinged: Bool = true) -> some View {
        overlay {
            if isRinged {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.keaserInk, lineWidth: 1.5)
                    .padding(2)
            }
        }
    }
}
