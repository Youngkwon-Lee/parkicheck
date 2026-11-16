import SwiftData
import SwiftUI

/// Add or edit a scheduled medication. Times are picked from common slots with one tap,
/// so the only typing is the medication name.
struct MedicationEditorView: View {
    let medication: Medication?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dose = ""
    @State private var minutes: Set<Int> = []
    @State private var customTime = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var confirmingDelete = false
    @State private var showingCatalog = false
    @State private var typingName = false
    @State private var typingDose = false

    static let presets: [(String, Int)] = [("아침 8시", 8 * 60), ("점심 12시", 12 * 60), ("오후 4시", 16 * 60),
                                           ("저녁 6시", 18 * 60), ("자기 전 10시", 22 * 60)]

    var body: some View {
        NavigationStack {
            ZStack {
                CoachBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CoachSectionHeader(title: "약 이름")
                        Button { showingCatalog = true } label: {
                            HStack {
                                Image(systemName: "list.bullet.rectangle.portrait").foregroundStyle(CoachStyle.accent)
                                Text(name.isEmpty ? "약 목록에서 고르기" : name)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(name.isEmpty ? CoachStyle.primary : CoachStyle.ink)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(CoachStyle.faint)
                            }
                            .padding(.horizontal, 14).frame(minHeight: CoachStyle.controlHeight)
                            .background(CoachStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CoachStyle.strokeStrong))
                        }
                        .buttonStyle(CoachPressStyle())
                        if typingName || (!name.isEmpty && !MedicationCatalog.contains(name)) {
                            TextField("", text: $name, prompt: Text("약 이름 입력").foregroundStyle(CoachStyle.faint)).coachField()
                        } else {
                            Button("목록에 없으면 직접 입력") { typingName = true }
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(CoachStyle.primary)
                                .frame(minHeight: 44)
                        }
                        CoachSectionHeader(title: "한 번에 드시는 양")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(MedicationCatalog.doseOptions, id: \.self) { option in
                                let on = dose == option
                                Button { dose = on ? "" : option } label: {
                                    Text(option).font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(on ? CoachStyle.onPrimary : CoachStyle.ink)
                                        .frame(maxWidth: .infinity, minHeight: CoachStyle.controlHeight)
                                        .background(on ? CoachStyle.primary : CoachStyle.raised, in: Capsule())
                                }
                                .buttonStyle(CoachPressStyle())
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        if typingDose || (!dose.isEmpty && !MedicationCatalog.doseOptions.contains(dose)) {
                            TextField("", text: $dose, prompt: Text("예: 100mg 1정").foregroundStyle(CoachStyle.faint)).coachField()
                        } else {
                            Button("다른 양 직접 입력") { typingDose = true }
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(CoachStyle.primary)
                                .frame(minHeight: 44)
                        }
                        CoachSectionHeader(title: "드시는 시간")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(Self.presets, id: \.1) { label, minute in
                                timeChip(label, minute: minute)
                            }
                        }
                        let custom = minutes.subtracting(Self.presets.map(\.1)).sorted()
                        if !custom.isEmpty {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(custom, id: \.self) { timeChip($0.clockLabel, minute: $0) }
                            }
                        }
                        HStack {
                            DatePicker("다른 시간", selection: $customTime, displayedComponents: .hourAndMinute)
                                .foregroundStyle(CoachStyle.ink)
                            Button("추가") {
                                let c = Calendar.current.dateComponents([.hour, .minute], from: customTime)
                                minutes.insert((c.hour ?? 0) * 60 + (c.minute ?? 0))
                            }
                            .buttonStyle(CoachSecondaryButtonStyle())
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .coachSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        if medication != nil {
                            Button("이 약 삭제", role: .destructive) { confirmingDelete = true }
                                .foregroundStyle(CoachStyle.danger)
                                .frame(maxWidth: .infinity, minHeight: CoachStyle.controlHeight)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(medication == nil ? "약 등록" : "약 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save).disabled(trimmedName.isEmpty || minutes.isEmpty)
                }
            }
            .sheet(isPresented: $showingCatalog) {
                MedicationCatalogPicker { picked in name = picked; typingName = false }
            }
            .confirmationDialog("이 약과 알림을 삭제할까요? 지난 복약 기록은 남아요.", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    if let medication { context.delete(medication); try? context.save() }
                    dismiss()
                }
            }
            .onAppear {
                guard let medication else { return }
                name = medication.name
                dose = medication.dose
                minutes = Set(medication.minutesOfDay)
            }
        }
        .preferredColorScheme(.light)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private func timeChip(_ label: String, minute: Int) -> some View {
        let on = minutes.contains(minute)
        return Button {
            if on { minutes.remove(minute) } else { minutes.insert(minute) }
        } label: {
            Label(label, systemImage: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? CoachStyle.onPrimary : CoachStyle.ink)
                .frame(maxWidth: .infinity, minHeight: CoachStyle.controlHeight)
                .background(on ? CoachStyle.primary : CoachStyle.raised, in: Capsule())
        }
        .buttonStyle(CoachPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func save() {
        if let medication {
            medication.name = trimmedName
            medication.dose = dose
            medication.minutesOfDay = minutes.sorted()
        } else {
            context.insert(Medication(name: trimmedName, dose: dose, minutesOfDay: Array(minutes)))
        }
        try? context.save()
        Task {
            if await NotificationManager.shared.authorizationStatus() == .notDetermined {
                await NotificationManager.shared.requestAuthorization()
            }
        }
        dismiss()
    }
}
