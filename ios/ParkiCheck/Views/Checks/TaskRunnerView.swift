import AVFoundation
import Combine
import SwiftData
import SwiftUI

@MainActor
final class TaskRecorder: ObservableObject {
    enum Phase: Equatable {
        case ready
        case countdown(Int)
        case recording(remaining: Int)
        case finished([Metric])
    }

    let kind: TaskKind
    let side: Hand?
    let tracker: MotionTracker

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var liveCount: Int?
    @Published private(set) var prompt: String?

    private var analyzer: any TaskAnalyzer
    private var timerTask: Task<Void, Never>?
    private var trackerChanges: AnyCancellable?
    private let speech = AVSpeechSynthesizer()
    private(set) var startedAt = Date()

    init(kind: TaskKind, side: Hand?) {
        self.kind = kind
        self.side = side
        tracker = MotionTracker(tracking: kind.tracking)
        analyzer = kind.makeAnalyzer(side: side)
        trackerChanges = tracker.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        tracker.onFrame = { [weak self] frame in
            guard let self, case .recording = self.phase else { return }
            self.analyzer.process(frame)
            self.liveCount = self.analyzer.liveCount
        }
    }

    func begin() {
        timerTask?.cancel()
        timerTask = Task {
            for n in stride(from: kind.countdownSec, through: 1, by: -1) {
                phase = .countdown(n)
                if n <= 3 { say("\(n)") }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            analyzer = kind.makeAnalyzer(side: side)
            liveCount = analyzer.liveCount
            startedAt = Date()
            say("시작")
            for remaining in stride(from: kind.durationSec, through: 1, by: -1) {
                phase = .recording(remaining: remaining)
                updatePrompt(elapsed: kind.durationSec - remaining)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            prompt = nil
            say("끝")
            phase = .finished(analyzer.metrics(durationSec: Double(kind.durationSec)))
        }
    }

    private func updatePrompt(elapsed: Int) {
        guard kind == .facialExpression else { return }
        let window = FaceAnalyzer.smileWindow
        if elapsed == Int(window.lowerBound) { prompt = "크게 웃어 주세요"; say("크게 웃어 주세요") }
        if elapsed == Int(window.upperBound) { prompt = "편하게 계세요"; say("편하게 계세요") }
    }

    private func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        speech.speak(utterance)
    }

    func reset() {
        timerTask?.cancel()
        phase = .ready
        liveCount = nil
        prompt = nil
    }

    /// Discards an interrupted countdown or recording (e.g. leaving the screen), so a partial
    /// recording is never computed over the full duration and saved.
    func cancelIfUnfinished() {
        if case .finished = phase { return }
        reset()
    }
}

struct TaskRunnerView: View {
    let kind: TaskKind
    let side: Hand?
    var stepLabel: String?
    var onSaved: () -> Void = {}

    @StateObject private var recorder: TaskRecorder
    @Environment(\.modelContext) private var context

    init(kind: TaskKind, side: Hand?, stepLabel: String? = nil, onSaved: @escaping () -> Void = {}) {
        self.kind = kind
        self.side = side
        self.stepLabel = stepLabel
        self.onSaved = onSaved
        _recorder = StateObject(wrappedValue: TaskRecorder(kind: kind, side: side))
    }

    private var tracker: MotionTracker { recorder.tracker }
    private var title: String { [side?.label, kind.title].compactMap { $0 }.joined(separator: " ") }

    var body: some View {
        Group {
            if case .finished(let metrics) = recorder.phase {
                TaskResultView(kind: kind, side: side, metrics: metrics, stepLabel: stepLabel,
                               onSave: { note in save(metrics, note: note) }, onRetry: recorder.reset)
            } else {
                cameraStage
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CoachStyle.surface, for: .navigationBar)
        .task { await tracker.start() }
        .onDisappear {
            recorder.cancelIfUnfinished()
            tracker.stop()
        }
    }

    @ViewBuilder private var cameraStage: some View {
        switch tracker.status {
        case .unauthorized:
            unavailable(symbol: "camera.fill", title: "카메라 권한이 필요해요",
                        detail: "설정 앱에서 ParkiCheck의 카메라 접근을 허용해 주세요. 영상은 기기 밖으로 나가지 않아요.", showSettings: true)
        case .unavailable:
            unavailable(symbol: "camera.badge.ellipsis", title: "카메라를 사용할 수 없어요",
                        detail: "전면 카메라가 있는 iPhone에서 기록할 수 있어요.", showSettings: false)
        case .idle, .running:
            ZStack {
                CameraPreview(session: tracker.session).ignoresSafeArea()
                HandOverlay(overlay: tracker.overlay).ignoresSafeArea()
                VStack(spacing: 12) {
                    statusBanner
                    if let prompt = recorder.prompt {
                        Text(prompt).font(.system(size: 28, weight: .bold)).foregroundStyle(CoachStyle.onPrimary)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(CoachStyle.primary, in: Capsule())
                    }
                    Spacer()
                    if recorder.phase == .ready { readyPanel }
                }
                .padding(20)
            }
        }
    }

    private var statusBanner: some View {
        Text(bannerText)
            .font(.system(size: bannerIsBig ? 44 : 18, weight: .bold))
            .foregroundStyle(CoachStyle.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .coachGlass(Capsule())
            .contentTransition(.numericText())
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var bannerIsBig: Bool {
        if case .countdown = recorder.phase { return true }
        return false
    }

    private var bannerText: String {
        switch recorder.phase {
        case .ready:
            return tracker.overlay == nil ? targetHint : "준비되면 시작을 누르세요"
        case .countdown(let n): return "\(n)"
        case .recording(let remaining):
            if let count = recorder.liveCount { return "\(remaining)초 · \(count)회" }
            return "\(remaining)초"
        case .finished: return ""
        }
    }

    private var targetHint: String {
        switch kind.group {
        case .hand: return "손 전체가 화면에 보이게 해 주세요"
        case .body: return "몸이 화면에 보이게 서 주세요"
        case .face: return "얼굴이 화면에 보이게 해 주세요"
        }
    }

    private var readyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stepLabel {
                Text(stepLabel).font(.system(size: 14, weight: .bold)).foregroundStyle(CoachStyle.accent)
            }
            Text(kind.instruction(side: side)).font(.system(size: 18, weight: .semibold)).foregroundStyle(CoachStyle.ink)
            Text("\(kind.setup) \(kind.durationSec)초 동안 기록해요.").font(.body).foregroundStyle(CoachStyle.quiet)
            Button("시작") { recorder.begin() }
                .buttonStyle(CoachPrimaryButtonStyle(fullWidth: true))
                .disabled(tracker.status != .running)
        }
        .padding(16)
        .coachGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func unavailable(symbol: String, title: String, detail: String, showSettings: Bool) -> some View {
        ZStack {
            CoachBackground()
            VStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(CoachStyle.accent)
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(CoachStyle.ink)
                Text(detail).font(.body).foregroundStyle(CoachStyle.quiet).multilineTextAlignment(.center)
                if showSettings {
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(CoachPrimaryButtonStyle())
                }
            }
            .padding(32)
        }
    }

    private func save(_ metrics: [Metric], note: String) {
        context.insert(TaskResult(kind: kind, side: side, startedAt: recorder.startedAt,
                                  durationSec: Double(kind.durationSec), metrics: metrics, note: note))
        try? context.save()
        onSaved()
    }
}

struct TaskResultView: View {
    let kind: TaskKind
    let side: Hand?
    let metrics: [Metric]
    var stepLabel: String?
    let onSave: (String) -> Void
    let onRetry: () -> Void
    @State private var note = ""

    private var looksEmpty: Bool {
        if let count = metrics.first(where: { ["count", "steps"].contains($0.key) })?.value { return count < 3 }
        if let frames = metrics.first(where: { $0.key == "frames" })?.value { return frames < 30 }
        if let tracked = metrics.first(where: { $0.key == "trackedSec" })?.value { return tracked < 4 }
        return false
    }

    var body: some View {
        ZStack {
            CoachBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CoachScreenTitle(title: "기록했어요", subtitle: "\([side?.label, kind.title].compactMap { $0 }.joined(separator: " ")) · \(kind.durationSec)초")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(metrics) { CoachStat(title: $0.label, value: $0.formatted) }
                    }
                    if looksEmpty {
                        CoachNotice(symbol: "exclamationmark.triangle.fill",
                                    text: "움직임이 거의 감지되지 않았어요. 화면에 잘 보이는지 확인하고 다시 기록해 보세요.")
                    }
                    CoachNotice(symbol: "info.circle.fill",
                                text: "촬영 환경에 따라 수치가 달라질 수 있어요. 진단이나 치료 판단에 쓰이지 않아요.")
                    CoachSectionHeader(title: "메모")
                    TextField("", text: $note, prompt: Text("예: 약 먹고 1시간 뒤, 피곤함").foregroundStyle(CoachStyle.quiet), axis: .vertical)
                        .coachField()
                    Button(stepLabel == nil ? "저장" : "저장하고 다음") { onSave(note) }
                        .buttonStyle(CoachPrimaryButtonStyle(fullWidth: true))
                    Button("다시 기록", action: onRetry)
                        .buttonStyle(CoachSecondaryButtonStyle(fullWidth: true))
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
    }
}
