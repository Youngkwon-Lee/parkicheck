import SwiftData
import SwiftUI

enum CheckRoute: Hashable {
    case daily
    case task(TaskKind, Hand?)
}

struct ChecksView: View {
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \TaskResult.startedAt, order: .reverse) private var results: [TaskResult]

    var body: some View {
        NavigationStack(path: $router.checksPath) {
            ZStack {
                CoachBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CoachScreenTitle(title: "검사", subtitle: "움직임을 카메라로 기록해요. 영상은 저장되지 않아요.")
                        dailyCard
                        ForEach(TaskKind.Group.allCases, id: \.self) { group in
                            CoachSectionHeader(title: group.rawValue)
                            if group == .body {
                                CoachNotice(symbol: "person.2.fill", text: TaskKind.posture.setup)
                            }
                            VStack(spacing: 10) {
                                ForEach(TaskKind.allCases.filter { $0.group == group }) { kind in
                                    TaskRow(kind: kind, last: results.first { $0.kind == kind })
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.bottom, 24, for: .scrollContent)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CheckRoute.self) { route in
                switch route {
                case .daily: DailyCheckFlowView()
                case .task(let kind, let side): TaskRunnerView(kind: kind, side: side) { router.checksPath.removeLast() }
                }
            }
        }
    }

    private var dailyCard: some View {
        let done = DailyCheck.completedToday(results: results, now: Date())
        let total = DailyCheck.steps.count
        return VStack(alignment: .leading, spacing: 10) {
            Label(done >= total ? "완료" : "매일", systemImage: done >= total ? "checkmark.circle.fill" : "sun.max.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(done >= total ? CoachStyle.ok : CoachStyle.accent)
            Text("오늘의 체크 · 약 2분").font(.system(size: 20, weight: .bold)).foregroundStyle(CoachStyle.ink)
            Text("오른손, 왼손 순서로 손가락 탭핑을 기록해요. (\(done)/\(total))")
                .font(.body).foregroundStyle(CoachStyle.ink.opacity(0.86))
            if done < total {
                NavigationLink(value: CheckRoute.daily) { Text(done == 0 ? "시작하기" : "이어서 하기") }
                    .buttonStyle(CoachPrimaryButtonStyle())
            }
        }
        .coachCard(accent: done < total ? CoachStyle.accent : nil)
    }
}

struct TaskRow: View {
    let kind: TaskKind
    let last: TaskResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                Image(systemName: kind.symbol).font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CoachStyle.accent)
                    .frame(width: 44, height: 44)
                    .background(CoachStyle.raised, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(CoachStyle.ink)
                    Text(lastText).font(.subheadline).foregroundStyle(CoachStyle.quiet)
                }
                Spacer(minLength: 0)
                if !kind.needsSide {
                    NavigationLink(value: CheckRoute.task(kind, nil)) { Text("시작") }
                        .buttonStyle(CoachSecondaryButtonStyle())
                }
            }
            if kind.needsSide {
                HStack(spacing: 8) {
                    ForEach([Hand.right, .left]) { side in
                        NavigationLink(value: CheckRoute.task(kind, side)) { Text(side.sideLabel) }
                            .buttonStyle(CoachSecondaryButtonStyle(fullWidth: true))
                    }
                }
            }
        }
        .padding(14)
        .coachSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var lastText: String {
        guard let last else { return "\(kind.durationSec)초 · 아직 기록 없음" }
        return "\(kind.durationSec)초 · 최근 \(last.startedAt.formatted(.relative(presentation: .named)))"
    }
}

/// Runs the daily steps in order, resuming from the first step not done today.
struct DailyCheckFlowView: View {
    @Query(sort: \TaskResult.startedAt, order: .reverse) private var results: [TaskResult]
    @EnvironmentObject private var router: AppRouter
    @State private var index: Int?
    @State private var finished = false

    var body: some View {
        Group {
            if finished || (index == nil && DailyCheck.nextStepIndex(results: results, now: Date()) == nil) {
                done
            } else if let index {
                let step = DailyCheck.steps[index]
                TaskRunnerView(kind: step.0, side: step.1, stepLabel: "오늘의 체크 \(index + 1)/\(DailyCheck.steps.count)") {
                    if index + 1 < DailyCheck.steps.count { self.index = index + 1 } else { finished = true }
                }
                .id(index)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if index == nil { index = DailyCheck.nextStepIndex(results: results, now: Date()) }
        }
    }

    private var done: some View {
        ZStack {
            CoachBackground()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(CoachStyle.ok)
                Text("오늘의 체크를 마쳤어요").font(.system(size: 24, weight: .bold)).foregroundStyle(CoachStyle.ink)
                Text("기록은 기록 탭에서 볼 수 있어요.").font(.body).foregroundStyle(CoachStyle.quiet)
                Button("홈으로") {
                    router.checksPath = NavigationPath()
                    router.tab = .home
                }
                .buttonStyle(CoachPrimaryButtonStyle())
            }
            .padding(32)
        }
        .navigationBarBackButtonHidden()
    }
}
