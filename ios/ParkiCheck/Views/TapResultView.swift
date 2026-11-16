import SwiftUI

/// Shared rows describing one recording's measurements. No score or interpretation.
struct MetricRows: View {
    let tapCount: Int
    let tapsPerSecond: Double
    let medianIntervalMs: Double?
    let intervalCVPercent: Double?
    let meanAmplitude: Double?
    let amplitudeDecrementPercent: Double?
    let pauseCount: Int

    var body: some View {
        LabeledContent("탭 횟수", value: "\(tapCount)회")
        LabeledContent("초당 탭", value: tapsPerSecond.formatted(.number.precision(.fractionLength(1))))
        LabeledContent("탭 간격(중앙값)", value: medianIntervalMs.map { "\(Int($0.rounded()))ms" } ?? "—")
        LabeledContent("간격 변동", value: intervalCVPercent.map { "\(Int($0.rounded()))%" } ?? "—")
        LabeledContent("평균 벌림 크기", value: meanAmplitude.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—")
        LabeledContent("후반부 벌림 감소", value: amplitudeDecrementPercent.map { "\(Int($0.rounded()))%" } ?? "—")
        LabeledContent("멈춤(0.6초 이상)", value: "\(pauseCount)회")
    }
}

extension MetricRows {
    init(_ m: TapMetrics) {
        self.init(tapCount: m.tapCount, tapsPerSecond: m.tapsPerSecond, medianIntervalMs: m.medianIntervalMs,
                  intervalCVPercent: m.intervalCVPercent, meanAmplitude: m.meanAmplitude,
                  amplitudeDecrementPercent: m.amplitudeDecrementPercent, pauseCount: m.pauseCount)
    }

    init(_ s: TapSession) {
        self.init(tapCount: s.tapCount, tapsPerSecond: s.tapsPerSecond, medianIntervalMs: s.medianIntervalMs,
                  intervalCVPercent: s.intervalCVPercent, meanAmplitude: s.meanAmplitude,
                  amplitudeDecrementPercent: s.amplitudeDecrementPercent, pauseCount: s.pauseCount)
    }
}

struct TapResultView: View {
    let metrics: TapMetrics
    let hand: Hand
    let onSave: (String) -> Void
    let onRetry: () -> Void
    @State private var note = ""

    var body: some View {
        Form {
            Section {
                MetricRows(metrics)
            } header: {
                Text("\(hand.label) · \(Int(metrics.durationSec))초 기록")
            } footer: {
                Text("기록된 수치는 촬영 환경에 따라 달라질 수 있으며 진단이나 치료 판단에 쓰이지 않습니다.")
            }
            if metrics.tapCount < 5 {
                Section {
                    Label("탭이 거의 감지되지 않았습니다. 손 전체가 화면에 보이는지 확인한 뒤 다시 기록해 보세요.",
                          systemImage: "exclamationmark.triangle")
                }
            }
            Section("메모") {
                TextField("예: 약 복용 1시간 후, 피곤함", text: $note, axis: .vertical)
            }
            Section {
                Button("저장") { onSave(note) }.frame(maxWidth: .infinity)
                Button("다시 기록", role: .destructive, action: onRetry).frame(maxWidth: .infinity)
            }
        }
    }
}
