import Foundation

/// The two kinds of label an account owns. They share one list screen and one
/// editor, so the differences live here.
public enum LabelKind: String, CaseIterable, Hashable, Sendable {
    case category
    case paymentMethod

    /// "Category", for "New Category" and "Edit Category".
    public var singularTitle: String {
        switch self {
        case .category: "Category"
        case .paymentMethod: "Payment Method"
        }
    }

    /// Screen title: "Categories".
    public var pluralTitle: String {
        switch self {
        case .category: "Categories"
        case .paymentMethod: "Payment Methods"
        }
    }

    /// The symbols the editor offers, in grid order.
    public var choices: [SymbolChoice] {
        switch self {
        case .category: SymbolCatalog.categories
        case .paymentMethod: SymbolCatalog.paymentMethods
        }
    }
}

/// A symbol the user can pick, and the name the editor suggests for it.
public struct SymbolChoice: Identifiable, Hashable, Sendable {
    /// SF Symbol name. Every one is available on iOS 18.
    public let symbol: String
    public let suggestedName: String

    public init(_ symbol: String, _ suggestedName: String) {
        self.symbol = symbol
        self.suggestedName = suggestedName
    }

    public var id: String { symbol }
}

/// Curated symbol sets for the label editor. The default categories and
/// payment methods are included, so editing one shows its symbol selected.
public enum SymbolCatalog {
    public static let categories: [SymbolChoice] = [
        // Food and drink
        SymbolChoice("fork.knife", "Food & Drinks"),
        SymbolChoice("cup.and.saucer.fill", "Coffee"),
        SymbolChoice("mug.fill", "Tea"),
        SymbolChoice("wineglass.fill", "Drinks"),
        SymbolChoice("birthday.cake.fill", "Desserts"),
        SymbolChoice("takeoutbag.and.cup.and.straw.fill", "Takeout"),
        SymbolChoice("carrot.fill", "Groceries"),
        // Shopping
        SymbolChoice("cart.fill", "Shopping"),
        SymbolChoice("basket.fill", "Supermarket"),
        SymbolChoice("bag.fill", "Retail"),
        SymbolChoice("tshirt.fill", "Clothing"),
        SymbolChoice("shoe.fill", "Shoes"),
        SymbolChoice("handbag.fill", "Accessories"),
        SymbolChoice("shippingbox.fill", "Online Orders"),
        // Travel
        SymbolChoice("airplane", "Travel"),
        SymbolChoice("suitcase.rolling.fill", "Trips"),
        SymbolChoice("bed.double.fill", "Hotels"),
        SymbolChoice("beach.umbrella.fill", "Holidays"),
        SymbolChoice("tent.fill", "Camping"),
        // Transport
        SymbolChoice("car.fill", "Transportation"),
        SymbolChoice("fuelpump.fill", "Fuel"),
        SymbolChoice("bus.fill", "Public Transit"),
        SymbolChoice("tram.fill", "Train"),
        SymbolChoice("bicycle", "Cycling"),
        SymbolChoice("parkingsign.circle.fill", "Parking"),
        // Home
        SymbolChoice("house.fill", "Home"),
        SymbolChoice("key.fill", "Rent"),
        SymbolChoice("sofa.fill", "Furniture"),
        SymbolChoice("washer.fill", "Laundry"),
        SymbolChoice("hammer.fill", "Repairs"),
        SymbolChoice("leaf.fill", "Garden"),
        // Bills and utilities
        SymbolChoice("bolt.fill", "Electricity"),
        SymbolChoice("drop.fill", "Water"),
        SymbolChoice("flame.fill", "Heating"),
        SymbolChoice("wifi", "Internet"),
        SymbolChoice("phone.fill", "Phone"),
        SymbolChoice("doc.text.fill", "Bills"),
        SymbolChoice("wrench.and.screwdriver.fill", "Services"),
        // Health
        SymbolChoice("heart.fill", "Health"),
        SymbolChoice("cross.case.fill", "Medical"),
        SymbolChoice("pills.fill", "Pharmacy"),
        SymbolChoice("dumbbell.fill", "Fitness"),
        SymbolChoice("scissors", "Personal Care"),
        // Education
        SymbolChoice("graduationcap.fill", "Education"),
        SymbolChoice("book.fill", "Books"),
        SymbolChoice("pencil.and.ruler.fill", "Supplies"),
        // Entertainment
        SymbolChoice("gamecontroller.fill", "Entertainment"),
        SymbolChoice("film.fill", "Movies"),
        SymbolChoice("music.note", "Music"),
        SymbolChoice("ticket.fill", "Events"),
        SymbolChoice("tv.fill", "Streaming"),
        SymbolChoice("theatermasks.fill", "Theatre"),
        // Pets
        SymbolChoice("pawprint.fill", "Pets"),
        SymbolChoice("dog.fill", "Dog"),
        SymbolChoice("cat.fill", "Cat"),
        // Gifts
        SymbolChoice("gift.fill", "Gifts"),
        SymbolChoice("party.popper.fill", "Celebrations"),
        SymbolChoice("heart.circle.fill", "Donations"),
        // Work
        SymbolChoice("briefcase.fill", "Work"),
        SymbolChoice("laptopcomputer", "Electronics"),
        SymbolChoice("printer.fill", "Office"),
        // Kids
        SymbolChoice("figure.and.child.holdinghands", "Family"),
        SymbolChoice("stroller.fill", "Baby"),
        SymbolChoice("teddybear.fill", "Toys"),
        SymbolChoice("backpack.fill", "School"),
    ]

    public static let paymentMethods: [SymbolChoice] = [
        SymbolChoice("creditcard.fill", "Credit Card"),
        SymbolChoice("creditcard.and.123", "Debit Card"),
        SymbolChoice("banknote.fill", "Cash"),
        SymbolChoice("building.columns.fill", "Bank Transfer"),
        SymbolChoice("wallet.bifold.fill", "E-Wallet"),
        SymbolChoice("iphone", "Mobile Pay"),
        SymbolChoice("wave.3.right.circle.fill", "Contactless"),
        SymbolChoice("wallet.pass.fill", "Store Card"),
        SymbolChoice("creditcard.circle.fill", "Virtual Card"),
        SymbolChoice("giftcard.fill", "Gift Card"),
        SymbolChoice("qrcode", "QR Payment"),
        SymbolChoice("arrow.left.arrow.right", "Money Transfer"),
        SymbolChoice("repeat.circle.fill", "Direct Debit"),
        SymbolChoice("clock.arrow.circlepath", "Pay Later"),
        SymbolChoice("briefcase.fill", "Company Card"),
        SymbolChoice("storefront.fill", "Store Credit"),
        SymbolChoice("signature", "Cheque"),
        SymbolChoice("dollarsign.circle.fill", "Balance"),
        SymbolChoice("bitcoinsign.circle.fill", "Crypto"),
        SymbolChoice("person.2.fill", "Shared"),
    ]
}

/// Naming rules shared by the category and payment method editors.
public enum LabelNaming {
    /// The name a label is saved under: the typed text, trimmed, or the
    /// chosen symbol's suggestion when nothing was typed. Nil when both are
    /// blank.
    public static func resolvedName(typed: String, suggestion: String?) -> String? {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let suggestion = suggestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return suggestion.isEmpty ? nil : suggestion
    }

    /// Whether another label already uses `name`, ignoring case and accents.
    /// Names must be unique because filters and Notion sync match labels by
    /// name.
    public static func isTaken(_ name: String, by existing: [(id: UUID, name: String)], excluding id: UUID?) -> Bool {
        let key = normalized(name)
        return existing.contains { $0.id != id && normalized($0.name) == key }
    }

    /// Where a new label starts: the first choice whose symbol is not already
    /// in use, or the first choice when every symbol is taken.
    public static func startingChoice(from choices: [SymbolChoice], usedSymbols: Set<String>) -> SymbolChoice? {
        choices.first { !usedSymbols.contains($0.symbol) } ?? choices.first
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
