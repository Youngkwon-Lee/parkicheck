import SwiftData
import SwiftUI

struct RecordHomeView: View {
    @Query(sort: \TapSession.startedAt, order: .reverse) private var sessions: [TapSession]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Hand.allCases) { hand in
                        NavigationLink {
                            TappingTestView(hand: hand)
                        } label: {
                            Label("\(hand.label) 탭핑 기록하기", systemImage: hand == .left ? "hand.raised" : "hand.raised.fill")
                                .padding(.vertical, 6)
                        }
                    }
                } header: {
                    Text("손가락 탭핑")
                } footer: {
                    Text("휴대폰을 세워 두고, 손이 화면에 모두 보이게 한 뒤 10초간 기록합니다.")
                }

                Section("최근 기록") {
                    if sessions.isEmpty {
                        Text("아직 기록이 없습니다.").foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions.prefix(5)) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                            }
                        }
                    }
                }
            }
            .navigationTitle("기록")
        }
    }
}

struct SessionRow: View {
    let session: TapSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(session.hand.label) · \(session.tapCount)회")
                .font(.headline)
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct SessionDetailView: View {
    @Bindable var session: TapSession

    var body: some View {
        Form {
            Section(session.startedAt.formatted(date: .long, time: .shortened)) {
                LabeledContent("손", value: session.hand.label)
                MetricRows(session)
            }
            Section("메모") {
                TextField("메모", text: $session.note, axis: .vertical)
            }
        }
        .navigationTitle("기록 상세")
        .navigationBarTitleDisplayMode(.inline)
    }
}
