import SwiftUI

// Swipe to edit or delete on Keaser's own rows (Home's Latest card and the
// search results), which sit in a lazy stack rather than a List. iOS 27 lets
// swipe actions work there once the scroll view coordinates them; earlier
// systems keep only the long-press menu, so both helpers do nothing there.

extension View {
    /// Swiping the row towards the leading edge reveals Delete and Edit, the
    /// same actions (and the same confirmation before deleting) as its
    /// long-press menu. A full swipe deletes. iOS 27 and later only; the
    /// scroll view holding the row needs `keaserSwipeActionsContainer()`.
    @ViewBuilder
    func keaserSwipeActions(onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        if #available(iOS 27.0, *) {
            swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.keaserSwipeAction)
            }
        } else {
            self
        }
    }

    /// Lets the rows inside this scroll view open their swipe actions, one
    /// row at a time; scrolling or tapping elsewhere closes an open row, as
    /// in a List. iOS 27 and later only.
    @ViewBuilder
    func keaserSwipeActionsContainer() -> some View {
        if #available(iOS 27.0, *) {
            swipeActionsContainer()
        } else {
            self
        }
    }
}
