import SwiftUI

/// Keaser's neutral stand-in for Notion wherever the service is named: a
/// rounded tile with a plain "N". Not Notion's logo, on purpose.
///
/// `.filled` is a white tile with a black letter (rows and headers);
/// `.outlined` is a black tile with a white outline (drawn beside the Keaser
/// logo, which is itself a white tile).
struct NotionMark: View {
    enum Style { case filled, outlined }

    var size: CGFloat = 36
    var style: Style = .filled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        Text("N")
            .font(.system(size: size * 0.54, weight: .bold))
            .foregroundStyle(style == .filled ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(style == .filled ? Color.white : Color.black, in: shape)
            .overlay {
                if style == .outlined {
                    shape.strokeBorder(Color.white, lineWidth: max(1.5, size * 0.07))
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Notion")
    }
}
