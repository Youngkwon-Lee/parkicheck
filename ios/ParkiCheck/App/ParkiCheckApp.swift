import SwiftData
import SwiftUI

@main
struct ParkiCheckApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [TapSession.self, MedicationEntry.self])
    }
}

struct RootView: View {
    @AppStorage("acceptedNoticeVersion") private var acceptedNoticeVersion = 0
    static let noticeVersion = 1

    var body: some View {
        TabView {
            RecordHomeView().tabItem { Label("기록", systemImage: "hand.tap") }
            TrendView().tabItem { Label("추이", systemImage: "chart.xyaxis.line") }
            MedicationLogView().tabItem { Label("복약", systemImage: "pills") }
            SettingsView().tabItem { Label("설정", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: .constant(acceptedNoticeVersion < Self.noticeVersion)) {
            NoticeView { acceptedNoticeVersion = Self.noticeVersion }
        }
    }
}

struct NoticeContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ParkiCheck는 손가락 탭핑 동작과 복약 시각을 스스로 기록하는 앱입니다.")
            Label("진단, 치료, 약 조절 판단을 하지 않습니다. 의료적 판단은 의료진과 상의하세요.", systemImage: "stethoscope")
            Label("카메라 영상은 기기 안에서만 처리하며 저장하거나 전송하지 않습니다.", systemImage: "lock.shield")
            Label("기록은 이 기기에만 저장되며, 직접 내보내거나 삭제할 수 있습니다.", systemImage: "iphone")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NoticeView: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("시작하기 전에").font(.largeTitle.bold())
            NoticeContent()
            Spacer()
            Button(action: onAccept) {
                Text("확인했습니다").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .interactiveDismissDisabled()
    }
}
