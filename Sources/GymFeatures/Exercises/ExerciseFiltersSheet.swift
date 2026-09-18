import SwiftUI
import GymCore
import GymUI

/// Il secondo livello dei filtri: attrezzo e "solo preferiti".
///
/// Sta in uno sheet perché nel catalogo servono raramente: in alto restano solo la
/// ricerca e i chip della zona colpita. I conteggi arrivano dalle facet di GymCore
/// e si aggiornano mentre si tocca.
public struct ExerciseFiltersSheet: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    @Binding private var model: ExerciseSearchModel

    /// - Parameter model: stato di ricerca condiviso con il catalogo o il picker.
    public init(model: Binding<ExerciseSearchModel>) {
        self._model = model
    }

    public var body: some View {
        let facets = app.store.exerciseFacets(for: model.filter)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                favoritesRow(count: facets.favorites)

                let equipment = equipmentRows(facets)
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Attrezzo")
                        .overlineStyle()

                    VStack(spacing: 0) {
                        ForEach(equipment) { facet in
                            equipmentRow(facet, showsSeparator: facet.id != equipment.last?.id)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .pageBackground()
    }

    // MARK: - Testata

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Button("Fine") { dismiss() }
                    .font(.bodyText)
                    .foregroundStyle(Theme.textSecondary)
                    .buttonStyle(.plain)
                    .frame(minHeight: Theme.Size.minTapTarget, alignment: .leading)

                Spacer(minLength: Theme.Spacing.s)

                if model.hasAnyFilter {
                    Button("Azzera") { model.clearFilters() }
                        .font(.bodyText)
                        .foregroundStyle(Theme.textSecondary)
                        .buttonStyle(.plain)
                        .frame(minHeight: Theme.Size.minTapTarget, alignment: .trailing)
                }
            }

            Text("Filtri")
                .sectionTitleStyle()
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Righe

    private func favoritesRow(count: Int) -> some View {
        toggleRow(
            title: "Solo preferiti",
            count: count,
            isOn: model.favoritesOnly,
            action: { model.favoritesOnly.toggle() }
        )
    }

    /// Solo gli attrezzi che darebbero risultati, più quelli già scelti.
    private func equipmentRows(_ facets: ExerciseFacets) -> [FacetCount] {
        var rows = facets.equipment
        let shown = Set(rows.map(\.value))
        for value in model.equipment.sorted() where !shown.contains(value) {
            rows.append(FacetCount(value: value, label: Localization.equipment(value), count: 0))
        }
        return rows
    }

    private func equipmentRow(_ facet: FacetCount, showsSeparator: Bool) -> some View {
        VStack(spacing: 0) {
            toggleRow(
                title: facet.label,
                count: facet.count,
                isOn: model.equipment.contains(facet.value),
                action: { model.toggleEquipment(facet.value) }
            )

            if showsSeparator {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: Theme.Size.hairline)
            }
        }
    }

    private func toggleRow(title: String, count: Int, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Text(title)
                    .font(.bodyText)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: Theme.Spacing.s)

                Text("\(count)")
                    .font(.captionText)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(.body, weight: .regular))
                    .foregroundStyle(isOn ? Theme.accent.deep : Theme.textTertiary)
            }
            .frame(minHeight: Theme.Size.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(count) esercizi"))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
