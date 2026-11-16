import SwiftUI

/// Light patient theme using the Kinelo client (member) app palette — values mirror
/// physio_app `mobile/health-sync/src/client-theme.ts` (iOS 1.0.0 light baseline) — with
/// Kinelo Coach's component grammar (opaque cards, pill buttons, floating glass tab bar).
/// Sizes are raised for older users and hand tremor: body 17pt, controls at least 52pt tall.
enum CoachStyle {
    static let background = Color(hex: 0xF5F7F6)
    static let surface = Color.white
    /// Raised / selected fill (client `surfaceMuted`).
    static let raised = Color(hex: 0xEAF3EF)
    /// The one emphasis surface per screen (client `hero`, cream).
    static let hero = Color(hex: 0xF7F1E5)
    static let ink = Color(hex: 0x14231F)
    static let quiet = Color(hex: 0x56635E)
    static let faint = Color(hex: 0x65706C)
    static let stroke = Color(hex: 0xE6EBE8)
    static let strokeStrong = Color(hex: 0xD5DDD9)
    /// Forest action color; white labels on it are 7.6:1.
    static let primary = Color(hex: 0x205C53)
    static let primaryPressed = Color(hex: 0x17453E)
    static let onPrimary = Color.white
    /// Icon and kicker tint (client `heroKicker`).
    static let accent = Color(hex: 0x2F7468)

    static let ok = Color(hex: 0x2F7468)
    static let warn = Color(hex: 0x8A5A12)
    static let warnSoft = Color(hex: 0xF7F1E5)
    static let danger = Color(hex: 0xAF3C40)
    static let dangerSoft = Color(hex: 0xF7EBEB)

    static let controlHeight: CGFloat = 52
    static let screenPadding: CGFloat = 20

    static func tint(for state: PatientState) -> Color {
        switch state {
        case .good: return ok
        case .off: return warn
        case .dyskinesia: return danger
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct CoachBackground: View {
    var body: some View {
        CoachStyle.background.ignoresSafeArea()
    }
}

extension View {
    /// Liquid Glass on iOS 26+, translucent material before that. Reserved for floating controls.
    @ViewBuilder
    func coachGlass<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(tint.map { .regular.tint($0.opacity(0.18)) } ?? .regular.interactive(), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(CoachStyle.stroke))
        }
    }

    /// Content surface: opaque white card with a hairline.
    func coachSurface<S: InsettableShape>(_ shape: S, accent: Color? = nil) -> some View {
        self.background(CoachStyle.surface, in: shape)
            .overlay(shape.strokeBorder(accent?.opacity(0.45) ?? CoachStyle.stroke, lineWidth: 1))
    }

    func coachCard(accent: Color? = nil) -> some View {
        self.padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .coachSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), accent: accent)
    }

    /// The single cream emphasis card for a screen (what to do next).
    func coachHero() -> some View {
        self.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CoachStyle.hero, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    func coachField() -> some View {
        self.font(.body).foregroundStyle(CoachStyle.ink)
            .padding(.horizontal, 14).frame(minHeight: CoachStyle.controlHeight)
            .background(CoachStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CoachStyle.strokeStrong))
    }
}

struct CoachPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CoachPrimaryButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold)).foregroundStyle(CoachStyle.onPrimary)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: CoachStyle.controlHeight)
            .background(configuration.isPressed ? CoachStyle.primaryPressed : CoachStyle.primary, in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CoachSecondaryButtonStyle: ButtonStyle {
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold)).foregroundStyle(CoachStyle.primary)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: CoachStyle.controlHeight)
            .background(CoachStyle.raised.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CoachScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(CoachStyle.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.body).foregroundStyle(CoachStyle.quiet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CoachSectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(CoachStyle.quiet)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

struct CoachStat: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(CoachStyle.quiet)
            Text(value).font(.system(size: 24, weight: .bold)).foregroundStyle(CoachStyle.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(CoachStyle.faint).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .coachSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct CoachNotice: View {
    let symbol: String
    let text: String
    var tone: Tone = .neutral

    enum Tone { case neutral, warning }

    var body: some View {
        Label {
            Text(text).font(.body).foregroundStyle(tone == .warning ? CoachStyle.warn : CoachStyle.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tone == .warning ? CoachStyle.warn : CoachStyle.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone == .warning ? CoachStyle.warnSoft : CoachStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tone == .warning ? .clear : CoachStyle.stroke))
    }
}

/// Large one-tap choice used for patient-reported state.
struct StateChoiceButton: View {
    let state: PatientState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: state.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CoachStyle.tint(for: state))
                    .frame(width: 40, height: 40)
                    .background(CoachStyle.raised, in: Circle())
                Text(state.label).font(.system(size: 18, weight: .semibold)).foregroundStyle(CoachStyle.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(CoachStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CoachStyle.strokeStrong))
            .contentShape(Rectangle())
        }
        .buttonStyle(CoachPressStyle())
    }
}
