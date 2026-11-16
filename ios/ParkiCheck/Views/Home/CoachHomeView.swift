import SwiftData
import SwiftUI
import UserNotifications

/// Home: one conversation with the on-device coach. The patient types or speaks; the coach
/// records and opens features, and offers one-tap answers.
struct CoachHomeView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: AppRouter
    @State private var agent: ParkiAgent?
    @State private var showingMedEditor = false
    @Query private var medications: [Medication]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let agent {
                CoachChat(agent: agent)
            } else {
                Spacer()
            }
        }
        .background(CoachBackground())
        .sheet(isPresented: $showingMedEditor) { MedicationEditorView(medication: nil) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Returning from the permission prompt or Settings: drop a stale "turn on alerts" card.
            Task {
                let authorized = await NotificationManager.shared.authorizationStatus() == .authorized
                agent?.refreshPriority(notificationsAuthorized: authorized)
            }
        }
        .onChange(of: medications.map { "\($0.id)\($0.minutesOfDay)\($0.isActive)" }) { _, _ in
            Task {
                let authorized = await NotificationManager.shared.authorizationStatus() == .authorized
                agent?.medicationsChanged(notificationsAuthorized: authorized)
            }
        }
        .task {
            guard agent == nil else { return }
            let made = ParkiAgent(context: context, router: router)
            made.openMedicationEditor = { showingMedEditor = true }
            made.requestNotifications = {
                await NotificationManager.shared.requestAuthorization()
                let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
                await NotificationManager.shared.reschedule(meds)
            }
            agent = made
            let authorized = await NotificationManager.shared.authorizationStatus() == .authorized
            made.greet(notificationsAuthorized: authorized)
        }
    }

    private var topBar: some View {
        HStack {
            Text("ParkiCheck").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(CoachStyle.primary)
            Spacer()
            Text(Date().formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR"))))
                .font(.subheadline.weight(.semibold)).foregroundStyle(CoachStyle.quiet)
        }
        .padding(.horizontal, 20).frame(minHeight: 52)
        .background(CoachStyle.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(CoachStyle.stroke).frame(height: 1) }
    }
}

private struct CoachChat: View {
    @ObservedObject var agent: ParkiAgent
    @StateObject private var speech = SpeechInput()
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let quickRequests = ["약 먹었어", "괜찮아", "몸이 굳어", "몸이 저절로 움직여", "오늘의 체크", "이번 주 요약"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(agent.messages) { message in
                            CoachMessageView(message: message) { action in
                                action.perform()
                                agent.consume(action.id, in: message.id)
                            }
                            .id(message.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: agent.messages.count) { _, _ in
                    guard let last = agent.messages.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .top) }
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: agent.messages.count)

            if speech.isRecording || speech.error != nil {
                Text(speech.error ?? (speech.transcript.isEmpty ? "듣고 있어요. 다 말하면 마이크를 다시 눌러 주세요." : speech.transcript))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(speech.error == nil ? CoachStyle.ink : CoachStyle.warn)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CoachStyle.hero, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 16).padding(.top, 6)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickRequests, id: \.self) { text in
                        Button(text) { agent.send(text) }
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(CoachStyle.primary)
                            .padding(.horizontal, 16).frame(minHeight: 46)
                            .background(CoachStyle.surface, in: Capsule())
                            .overlay(Capsule().stroke(CoachStyle.strokeStrong))
                            .buttonStyle(CoachPressStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)

            composer
        }
        .onAppear { speech.onFinish = { agent.send($0) } }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, prompt: Text("말하거나 적어 주세요").foregroundStyle(CoachStyle.faint), axis: .vertical)
                .lineLimit(1...4).focused($focused)
                .font(.system(size: 17)).foregroundStyle(CoachStyle.ink)
                .padding(.leading, 16).padding(.vertical, 12)
                .submitLabel(.send).onSubmit(submit)
            if draft.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: speech.toggle) {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(CoachStyle.onPrimary)
                        .frame(width: 48, height: 48)
                        .background(speech.isRecording ? CoachStyle.danger : CoachStyle.primary, in: Circle())
                        .symbolEffect(.pulse, isActive: speech.isRecording)
                }
                .buttonStyle(CoachPressStyle())
                .accessibilityLabel(speech.isRecording ? "말하기 끝내기" : "말로 기록하기")
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up").font(.system(size: 19, weight: .bold))
                        .foregroundStyle(CoachStyle.onPrimary).frame(width: 48, height: 48)
                        .background(CoachStyle.primary, in: Circle())
                }
                .buttonStyle(CoachPressStyle())
                .accessibilityLabel("보내기")
            }
        }
        .padding(.trailing, 5).padding(.vertical, 4)
        .background(CoachStyle.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CoachStyle.strokeStrong))
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func submit() {
        let text = draft
        draft = ""
        agent.send(text)
    }
}

private struct CoachMessageView: View {
    let message: ParkiAgent.Message
    let onAction: (ParkiAgent.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let question = message.question {
                Text(question).font(.system(size: 17, weight: .medium)).foregroundStyle(CoachStyle.onPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(CoachStyle.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            CardView(card: message.card, onAction: onAction)
        }
    }
}

private struct CardView: View {
    let card: ParkiAgent.Card
    let onAction: (ParkiAgent.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let status = card.status, let label = statusLabel(status) {
                Label(label.0, systemImage: label.1).font(.system(size: 14, weight: .bold)).foregroundStyle(label.2)
                    .symbolEffect(.bounce, value: card.title)
            }
            if let title = card.title {
                Text(title).font(.system(size: 19, weight: .bold)).foregroundStyle(CoachStyle.ink)
            }
            ForEach(card.lines, id: \.self) { Text($0).font(.system(size: 17)).foregroundStyle(CoachStyle.quiet) }
            if card.stacked {
                VStack(spacing: 8) {
                    ForEach(card.actions) { action in
                        if case .state(let state) = action.style {
                            StateChoiceButton(state: state) { onAction(action) }
                        } else {
                            button(action, fullWidth: true)
                        }
                    }
                }
            } else if !card.actions.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { ForEach(card.actions) { button($0, fullWidth: false) } }
                    VStack(spacing: 8) { ForEach(card.actions) { button($0, fullWidth: true) } }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.status == .proposal ? CoachStyle.hero : CoachStyle.surface,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(card.status == .proposal ? .clear : CoachStyle.stroke))
    }

    @ViewBuilder private func button(_ action: ParkiAgent.Action, fullWidth: Bool) -> some View {
        switch action.style {
        case .primary: Button(action.title) { onAction(action) }.buttonStyle(CoachPrimaryButtonStyle(fullWidth: fullWidth))
        default: Button(action.title) { onAction(action) }.buttonStyle(CoachSecondaryButtonStyle(fullWidth: fullWidth))
        }
    }

    private func statusLabel(_ status: ParkiAgent.Card.Status) -> (String, String, Color)? {
        switch status {
        case .proposal: return ("제안", "sparkles", CoachStyle.accent)
        case .done: return ("기록 완료", "checkmark.circle.fill", CoachStyle.ok)
        case .attention: return ("확인 필요", "exclamationmark.circle.fill", CoachStyle.warn)
        case .info: return nil
        }
    }
}
