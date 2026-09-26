import SwiftUI

/// Keaser's neutral stand-in for Notion wherever the service is named: a
/// black rounded tile with a white outline and a plain "N". Not Notion's
/// logo, on purpose.
struct NotionMark: View {
    var size: CGFloat = 36

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        Text("N")
            .font(.system(size: size * 0.54, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(Color.black, in: shape)
            .overlay(shape.strokeBorder(Color.white, lineWidth: max(1.5, size * 0.07)))
            .accessibilityElement()
            .accessibilityLabel("Notion")
    }
}
