import Combine
import SwiftData
import SwiftUI

@MainActor
final class TappingRecorder: ObservableObject {
    enum Phase: Equatable {
        case ready
        case countdown(Int)
        case recording(remaining: Int)
        case finished(TapMetrics)
    }

    static let durationSec = 10

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var liveTapCount = 0
    let tracker = HandTracker()

    private var detector = TapDetector()
    private var timerTask: Task<Void, Never>?
    private var trackerChanges: AnyCancellable?
    private(set) var startedAt = Date()

    init() {
        // Re-render views observing the recorder when camera status or overlay changes.
        trackerChanges = tracker.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        tracker.onSample = { [weak self] sample in
            guard let self, case .recording = self.phase else { return }
            if self.detector.process(sample) != nil { self.liveTapCount = self.detector.taps.count }
        }
    }

    func begin() {
        timerTask?.cancel()
        timerTask = Task {
            for n in stride(from: 3, through: 1, by: -1) {
                phase = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            detector = TapDetector()
            liveTapCount = 0
            startedAt = Date()
            for remaining in stride(from: Self.durationSec, through: 1, by: -1) {
                phase = .recording(remaining: remaining)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            phase = .finished(TapMetrics.compute(taps: detector.taps, durationSec: Double(Self.durationSec)))
        }
    }

    func reset() {
        timerTask?.cancel()
        phase = .ready
        liveTapCount = 0
    }

    /// Discards a countdown or recording that was interrupted (e.g. by switching tabs),
    /// so an incomplete recording can never be computed over the full duration and saved.
    func cancelIfUnfinished() {
        if case .finished = phase { return }
        reset()
    }
}

struct TappingTestView: View {
    let hand: Hand
    @StateObject private var recorder = TappingRecorder()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var tracker: HandTracker { recorder.tracker }

    var body: some View {
        Group {
            if case .finished(let metrics) = recorder.phase {
                TapResultView(metrics: metrics, hand: hand,
                              onSave: { note in save(metrics, note: note) },
                              onRetry: recorder.reset)
            } else {
                cameraStage
            }
        }
        .navigationTitle("\(hand.label) 탭핑 기록")
        .navigationBarTitleDisplayMode(.inline)
        .task { await tracker.start() }
        .onDisappear {
            recorder.cancelIfUnfinished()
            tracker.stop()
        }
    }

    @ViewBuilder private var cameraStage: some View {
        switch tracker.status {
        case .unauthorized:
            ContentUnavailableView {
                Label("카메라 권한이 필요합니다", systemImage: "camera.fill")
            } description: {
                Text("설정 앱에서 ParkiCheck의 카메라 접근을 허용해 주세요. 영상은 기기 밖으로 나가지 않습니다.")
            } actions: {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        case .unavailable:
            ContentUnavailableView("카메라를 사용할 수 없습니다", systemImage: "camera.badge.ellipsis",
                                   description: Text("전면 카메라가 있는 iPhone에서 기록할 수 있습니다."))
        case .idle, .running:
            ZStack {
                CameraPreview(session: tracker.session).ignoresSafeArea()
                HandOverlay(overlay: tracker.overlay).ignoresSafeArea()
                VStack {
                    statusBanner
                    Spacer()
                    controls
                }
                .padding()
            }
        }
    }

    private var statusBanner: some View {
        Text(bannerText)
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var bannerText: String {
        switch recorder.phase {
        case .ready:
            return tracker.overlay == nil ? "손 전체가 화면에 보이게 해 주세요" : "준비되면 시작을 누르세요"
        case .countdown(let n): return "\(n)"
        case .recording(let remaining): return "엄지와 검지를 크고 빠르게 · \(remaining)초 · \(recorder.liveTapCount)회"
        case .finished: return ""
        }
    }

    @ViewBuilder private var controls: some View {
        if recorder.phase == .ready {
            VStack(spacing: 12) {
                Text("엄지와 검지를 최대한 크게 벌렸다 붙이기를 \(TappingRecorder.durationSec)초 동안 반복합니다.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                Button {
                    recorder.begin()
                } label: {
                    Text("시작").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tracker.status != .running)
            }
        }
    }

    private func save(_ metrics: TapMetrics, note: String) {
        modelContext.insert(TapSession(startedAt: recorder.startedAt, hand: hand, metrics: metrics, note: note))
        dismiss()
    }
}
