import SwiftUI

/// The full-width white capsule: "Get Started", "Continue",
/// "Enable Notifications".
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: KeaserMetrics.primaryButtonHeight)
            .background(Capsule().fill(Color.white.opacity(isEnabled ? 1 : 0.4)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var keaserPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// An SF Symbol on a rounded dark tile, as in expense rows and the
/// onboarding sample rows.
struct SymbolTile: View {
    let symbol: String
    var size: CGFloat = 40
    var background: Color = .keaserCardRaised

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Centred symbol, title, message and optional action for empty screens.
/// `.large` is Home's version ("No Account", "No Expenses"): a bigger grey
/// symbol and 20pt text, measured from the reference.
struct EmptyStateView<Actions: View>: View {
    enum Style { case regular, large }

    let symbol: String
    let title: String
    let message: String
    var style: Style = .regular
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .keaserFont(style == .large ? 40 : 28)
                .foregroundStyle(style == .large ? Color.keaserMutedIcon : Color.white)
                .padding(.bottom, style == .large ? 21 : 14)
                .accessibilityHidden(true)
            Text(title)
                .keaserFont(style == .large ? 20 : 17, weight: .bold)
                .foregroundStyle(Color.keaserPrimaryText)
                .multilineTextAlignment(.center)
            Text(message)
                .keaserFont(style == .large ? 20 : 15)
                .foregroundStyle(Color.keaserSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, style == .large ? 3 : 4)
                .fixedSize(horizontal: false, vertical: true)
            actions
                .padding(.top, style == .large ? 30 : 16)
        }
        .frame(maxWidth: style == .large ? 260 : 280)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String, style: Style = .regular) {
        self.init(symbol: symbol, title: title, message: message, style: style) { EmptyView() }
    }
}
