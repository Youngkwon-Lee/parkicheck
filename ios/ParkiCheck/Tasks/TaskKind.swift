import Foundation

/// Movement tasks. Labels describe the movement only: no scale names, item numbers or scores
/// appear in the UI, consistent with positioning the app as a self-recording tool.
enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case fingerTapping, handMovements, pronationSupination, restTremor, posturalTremor
    case toeTapping, legAgility, posture, gait, facialExpression

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case hand = "손", body = "다리·몸", face = "얼굴"
    }

    enum Tracking { case hand, body, face }

    var group: Group {
        switch self {
        case .fingerTapping, .handMovements, .pronationSupination, .restTremor, .posturalTremor: return .hand
        case .toeTapping, .legAgility, .posture, .gait: return .body
        case .facialExpression: return .face
        }
    }

    var tracking: Tracking {
        switch group {
        case .hand: return .hand
        case .body: return .body
        case .face: return .face
        }
    }

    var title: String {
        switch self {
        case .fingerTapping: return "손가락 탭핑"
        case .handMovements: return "주먹 쥐었다 펴기"
        case .pronationSupination: return "손 뒤집기"
        case .restTremor: return "쉴 때 손 떨림"
        case .posturalTremor: return "팔 뻗었을 때 떨림"
        case .toeTapping: return "발끝 두드리기"
        case .legAgility: return "무릎 들기"
        case .posture: return "선 자세"
        case .gait: return "걷기"
        case .facialExpression: return "표정과 눈 깜빡임"
        }
    }

    var symbol: String {
        switch self {
        case .fingerTapping: return "hand.tap.fill"
        case .handMovements: return "hand.raised.fingers.spread.fill"
        case .pronationSupination: return "arrow.triangle.2.circlepath"
        case .restTremor: return "hand.raised.fill"
        case .posturalTremor: return "hand.point.right.fill"
        case .toeTapping: return "shoeprints.fill"
        case .legAgility: return "figure.step.training"
        case .posture: return "figure.stand"
        case .gait: return "figure.walk"
        case .facialExpression: return "face.smiling"
        }
    }

    var needsSide: Bool {
        switch self {
        case .posture, .gait, .facialExpression: return false
        default: return true
        }
    }

    var durationSec: Int {
        switch self {
        case .restTremor, .posturalTremor, .posture, .facialExpression: return 15
        case .gait: return 20
        default: return 10
        }
    }

    /// Body tasks need time to step back from the phone before recording starts.
    var countdownSec: Int { group == .body ? 8 : 3 }

    var setup: String {
        switch group {
        case .hand: return "휴대폰을 세워 두고, 손 전체가 화면에 보이게 해 주세요."
        case .body: return "휴대폰을 의자 높이에 세워 두고 2~3m 떨어져 주세요. 보호자가 도와주면 더 좋아요."
        case .face: return "휴대폰을 눈높이에 두고 얼굴 전체가 보이게 해 주세요."
        }
    }

    func instruction(side: Hand?) -> String {
        let s = side?.sideLabel ?? ""
        switch self {
        case .fingerTapping: return "\(s) 엄지와 검지를 최대한 크게 벌렸다 붙이기를 빠르게 반복해요."
        case .handMovements: return "\(s) 주먹을 꽉 쥐었다가 활짝 펴기를 크고 빠르게 반복해요."
        case .pronationSupination: return "\(s) 팔꿈치를 굽힌 채 손바닥이 위·아래를 향하도록 빠르게 뒤집어요."
        case .restTremor: return "\(s) 손을 무릎 위에 편하게 올려 두고 힘을 빼고 가만히 있어요."
        case .posturalTremor: return "\(s) 팔을 앞으로 쭉 뻗고 손바닥을 아래로 한 채 그대로 유지해요."
        case .toeTapping: return "\(s) 발꿈치는 바닥에 둔 채 발끝을 최대한 높고 빠르게 두드려요. 다리가 화면에 보여야 해요."
        case .legAgility: return "의자에 앉아 \(s) 무릎을 최대한 높이 들었다 내리기를 빠르게 반복해요."
        case .posture: return "카메라를 정면으로 보고 평소처럼 서 있어요. 머리부터 허리까지 보여야 해요."
        case .gait: return "카메라 앞을 옆으로 지나가듯 평소 속도로 왔다 갔다 걸어요. 넘어지지 않게 주변을 정리해 주세요."
        case .facialExpression: return "카메라를 편하게 바라봐요. 중간에 안내가 나오면 크게 웃어 주세요."
        }
    }

    var primaryMetricKey: String {
        switch self {
        case .fingerTapping, .handMovements, .pronationSupination, .toeTapping, .legAgility: return "rate"
        case .restTremor, .posturalTremor: return "amplitude"
        case .posture: return "lateralLean"
        case .gait: return "cadence"
        case .facialExpression: return "blinksPerMin"
        }
    }

    var primaryMetricLabel: String {
        switch self {
        case .fingerTapping, .handMovements, .toeTapping, .legAgility: return "초당 횟수"
        case .pronationSupination: return "초당 뒤집기"
        case .restTremor, .posturalTremor: return "떨림 크기"
        case .posture: return "몸통 옆기울기"
        case .gait: return "분당 걸음 수"
        case .facialExpression: return "분당 눈 깜빡임"
        }
    }

    func makeAnalyzer(side: Hand?) -> any TaskAnalyzer {
        switch self {
        case .fingerTapping: return FingerTappingAnalyzer()
        case .handMovements: return HandMovementAnalyzer()
        case .pronationSupination: return PronationAnalyzer()
        case .restTremor, .posturalTremor: return TremorAnalyzer()
        case .toeTapping: return LiftCycleAnalyzer.toeTapping(side: side ?? .right)
        case .legAgility: return LiftCycleAnalyzer.legAgility(side: side ?? .right)
        case .posture: return PostureAnalyzer()
        case .gait: return GaitAnalyzer()
        case .facialExpression: return FaceAnalyzer()
        }
    }
}

/// The two-minute daily check: finger tapping, right then left.
enum DailyCheck {
    static let steps: [(TaskKind, Hand)] = [(.fingerTapping, .right), (.fingerTapping, .left)]

    static func completedToday(results: [TaskResult], now: Date, calendar: Calendar = .current) -> Int {
        steps.filter { step in
            results.contains { $0.kind == step.0 && $0.side == step.1 && calendar.isDate($0.startedAt, inSameDayAs: now) }
        }.count
    }

    static func nextStepIndex(results: [TaskResult], now: Date, calendar: Calendar = .current) -> Int? {
        steps.firstIndex { step in
            !results.contains { $0.kind == step.0 && $0.side == step.1 && calendar.isDate($0.startedAt, inSameDayAs: now) }
        }
    }
}
