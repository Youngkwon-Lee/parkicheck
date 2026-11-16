import SwiftData
import SwiftUI

@main
struct ParkiCheckApp: App {
    private let container = AppSchema.makeContainer()

    init() {
        NotificationManager.shared.configure(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .tint(CoachStyle.primary)
        }
        .modelContainer(container)
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home, checks, records, my
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "홈"
        case .checks: return "검사"
        case .records: return "기록"
        case .my: return "마이"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "bubble.left.fill"
        case .checks: return "hand.tap.fill"
        case .records: return "chart.line.uptrend.xyaxis"
        case .my: return "person.fill"
        }
    }
}

/// Navigation shared across tabs so the home coach can open a check or the records screen.
@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var checksPath = NavigationPath()

    func openTask(_ kind: TaskKind, side: Hand?) {
        tab = .checks
        checksPath = NavigationPath()
        checksPath.append(CheckRoute.task(kind, side))
    }

    func startDailyCheck() {
        tab = .checks
        checksPath = NavigationPath()
        checksPath.append(CheckRoute.daily)
    }
}

struct RootView: View {
    @AppStorage("acceptedNoticeVersion") private var acceptedNoticeVersion = 0
    static let noticeVersion = 2
    @StateObject private var router = AppRouter()
    @Query private var medications: [Medication]

    var body: some View {
        ZStack {
            CoachBackground()
            Group {
                switch router.tab {
                case .home: CoachHomeView()
                case .checks: ChecksView()
                case .records: RecordsView()
                case .my: MyView()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { FloatingTabBar(selection: $router.tab) }
        .environmentObject(router)
        .fullScreenCover(isPresented: .constant(acceptedNoticeVersion < Self.noticeVersion)) {
            NoticeView { acceptedNoticeVersion = Self.noticeVersion }
        }
        .task(id: medications.map { "\($0.id)\($0.minutesOfDay)\($0.isActive)\($0.name)\($0.dose)" }) {
            await NotificationManager.shared.reschedule(medications)
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = tab }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.system(size: 21, weight: .semibold))
                        Text(tab.title).font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(selection == tab ? CoachStyle.primary : CoachStyle.faint)
                    .frame(maxWidth: .infinity).frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .coachGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 20).padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct NoticeContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ParkiCheck는 복약, 몸 상태, 움직임을 스스로 기록하는 앱입니다.")
                .font(.system(size: 18)).foregroundStyle(CoachStyle.ink)
            row("stethoscope", "진단, 치료, 약 조절 판단을 하지 않습니다. 의료적 판단은 의료진과 상의하세요.")
            row("lock.shield", "카메라 영상은 기기 안에서만 처리하며 저장하거나 전송하지 않습니다.")
            row("iphone", "기록은 이 기기에만 저장되며, 직접 내보내거나 삭제할 수 있습니다.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CoachStyle.accent).frame(width: 28)
            Text(text).font(.body).foregroundStyle(CoachStyle.ink.opacity(0.86))
        }
    }
}

struct NoticeView: View {
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            CoachBackground()
            VStack(alignment: .leading, spacing: 28) {
                Text("시작하기 전에").font(.system(size: 30, weight: .bold)).foregroundStyle(CoachStyle.ink)
                NoticeContent()
                Spacer()
                Button("확인했습니다", action: onAccept).buttonStyle(CoachPrimaryButtonStyle(fullWidth: true))
            }
            .padding(24)
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
    }
}
