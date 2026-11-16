import SwiftData
import SwiftUI

struct MedicationLogView: View {
    @Query(sort: \MedicationEntry.takenAt, order: .reverse) private var entries: [MedicationEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("복약 기록이 없습니다", systemImage: "pills")
                    } description: {
                        Text("복용한 약과 시각을 직접 기록해 두면 탭핑 기록과 함께 볼 수 있습니다.")
                    } actions: {
                        Button("복약 기록 추가") { showingAdd = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.dose.isEmpty ? entry.name : "\(entry.name) · \(entry.dose)").font(.headline)
                                Text(entry.takenAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if !entry.note.isEmpty { Text(entry.note).font(.footnote) }
                            }
                        }
                        .onDelete { offsets in offsets.map { entries[$0] }.forEach(modelContext.delete) }
                    }
                }
            }
            .navigationTitle("복약")
            .toolbar {
                Button { showingAdd = true } label: { Label("추가", systemImage: "plus") }
            }
            .sheet(isPresented: $showingAdd) { AddMedicationView() }
        }
    }
}

struct AddMedicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dose = ""
    @State private var takenAt = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("약 이름", text: $name)
                TextField("용량 (선택)", text: $dose)
                DatePicker("복용 시각", selection: $takenAt)
                TextField("메모 (선택)", text: $note, axis: .vertical)
            }
            .navigationTitle("복약 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        modelContext.insert(MedicationEntry(takenAt: takenAt, name: name.trimmingCharacters(in: .whitespaces),
                                                            dose: dose, note: note))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
