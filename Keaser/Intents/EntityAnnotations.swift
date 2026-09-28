import AppIntents
import SwiftUI

// On-screen awareness: views that show an expense or an account say which
// one, so with Keaser open Siri and Apple Intelligence can act on "this
// expense" or "the second one". Nothing changes on screen.

extension View {
    /// Marks the view as showing this expense. Does nothing for nil, or
    /// before iOS 18.4.
    func keaserEntity(expense id: UUID?) -> some View {
        modifier(EntityAnnotation(identifier: id.map { EntityIdentifier(for: ExpenseEntity.self, identifier: $0) }))
    }

    /// Marks the view as showing this account. Does nothing for nil, or
    /// before iOS 18.4.
    func keaserEntity(account id: UUID?) -> some View {
        modifier(EntityAnnotation(identifier: id.map { EntityIdentifier(for: AccountEntity.self, identifier: $0) }))
    }
}

private struct EntityAnnotation: ViewModifier {
    let identifier: EntityIdentifier?

    func body(content: Content) -> some View {
        if #available(iOS 18.4, *), let identifier {
            content.appEntityIdentifier(identifier)
        } else {
            content
        }
    }
}
