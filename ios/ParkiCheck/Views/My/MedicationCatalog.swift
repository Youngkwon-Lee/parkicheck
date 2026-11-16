import SwiftUI

/// Commonly prescribed Parkinson's medications, for picking instead of typing.
/// Names only (brand, with generic in parentheses); no strengths or dosing guidance,
/// because the prescription decides those. Anything else can be typed in.
enum MedicationCatalog {
    struct Drug: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let generic: String
    }

    struct Group: Identifiable {
        var id: String { title }
        let title: String
        let drugs: [Drug]
    }

    static let groups: [Group] = [
        Group(title: "레보도파 복합제", drugs: [
            Drug(name: "마도파", generic: "레보도파·벤세라지드"),
            Drug(name: "마도파 HBS", generic: "레보도파·벤세라지드 서방형"),
            Drug(name: "시네메트", generic: "레보도파·카비도파"),
            Drug(name: "시네메트 CR", generic: "레보도파·카비도파 서방형"),
            Drug(name: "스타레보", generic: "레보도파·카비도파·엔타카폰"),
        ]),
        Group(title: "도파민 효능제", drugs: [
            Drug(name: "미라펙스", generic: "프라미펙솔"),
            Drug(name: "미라펙스 서방정", generic: "프라미펙솔 서방형"),
            Drug(name: "리큅", generic: "로피니롤"),
            Drug(name: "리큅 서방정", generic: "로피니롤 서방형"),
            Drug(name: "뉴프로 패치", generic: "로티고틴"),
        ]),
        Group(title: "MAO-B 억제제", drugs: [
            Drug(name: "아질렉트", generic: "라사길린"),
            Drug(name: "셀레길린", generic: "셀레길린"),
            Drug(name: "사피나미드", generic: "사피나미드"),
        ]),
        Group(title: "COMT 억제제", drugs: [
            Drug(name: "콤탄", generic: "엔타카폰"),
            Drug(name: "온젠티스", generic: "오피카폰"),
        ]),
        Group(title: "기타", drugs: [
            Drug(name: "아만타딘", generic: "아만타딘"),
            Drug(name: "트리헥시페니딜", generic: "트리헥시페니딜"),
        ]),
    ]

    static func contains(_ name: String) -> Bool { groups.contains { $0.drugs.contains { $0.name == name } } }

    static let doseOptions = ["½정", "1정", "1½정", "2정", "3정", "패치 1매"]
}

struct MedicationCatalogPicker: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [MedicationCatalog.Group] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return MedicationCatalog.groups }
        return MedicationCatalog.groups.compactMap { group in
            let drugs = group.drugs.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.generic.contains(q) }
            return drugs.isEmpty ? nil : MedicationCatalog.Group(title: group.title, drugs: drugs)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CoachBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CoachNotice(symbol: "info.circle.fill", text: "처방전이나 약 봉투에 적힌 이름을 골라 주세요. 목록에 없으면 닫고 직접 입력하면 돼요.")
                        ForEach(filtered) { group in
                            CoachSectionHeader(title: group.title)
                            VStack(spacing: 0) {
                                ForEach(group.drugs) { drug in
                                    Button {
                                        onPick(drug.name)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(drug.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(CoachStyle.ink)
                                                if drug.generic != drug.name {
                                                    Text(drug.generic).font(.subheadline).foregroundStyle(CoachStyle.quiet)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(CoachStyle.primary)
                                        }
                                        .padding(.horizontal, 16).frame(minHeight: 64)
                                        .contentShape(Rectangle())
                                        .overlay(alignment: .bottom) { Rectangle().fill(CoachStyle.stroke).frame(height: 1).padding(.leading, 16) }
                                    }
                                    .buttonStyle(CoachPressStyle())
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .coachSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .padding(20)
                }
            }
            .searchable(text: $query, prompt: "약 이름 검색")
            .navigationTitle("약 고르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
}
