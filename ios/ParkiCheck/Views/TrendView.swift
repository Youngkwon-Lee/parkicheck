import Charts
import SwiftData
import SwiftUI

struct TrendView: View {
    @Query(sort: \TapSession.startedAt) private var sessions: [TapSession]
    @Query(sort: \MedicationEntry.takenAt) private var medications: [MedicationEntry]

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView("추이를 보려면 기록이 필요합니다", systemImage: "chart.xyaxis.line",
                                           description: Text("기록 탭에서 손가락 탭핑을 기록해 보세요."))
                } else {
                    List {
                        Section {
                            Chart {
                                ForEach(medications) { entry in
                                    RuleMark(x: .value("복약", entry.takenAt))
                                        .foregroundStyle(.secondary.opacity(0.4))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                }
                                ForEach(sessions) { session in
                                    LineMark(x: .value("날짜", session.startedAt),
                                             y: .value("초당 탭", session.tapsPerSecond))
                                        .foregroundStyle(by: .value("손", session.hand.label))
                                    PointMark(x: .value("날짜", session.startedAt),
                                              y: .value("초당 탭", session.tapsPerSecond))
                                        .foregroundStyle(by: .value("손", session.hand.label))
                                }
                            }
                            .frame(height: 240)
                            .accessibilityLabel("손별 초당 탭 횟수 추이")
                        } header: {
                            Text("초당 탭 횟수")
                        } footer: {
                            Text("점선은 직접 기록한 복약 시각입니다. 약효를 판단하지 않습니다.")
                        }
                    }
                }
            }
            .navigationTitle("추이")
        }
    }
}
