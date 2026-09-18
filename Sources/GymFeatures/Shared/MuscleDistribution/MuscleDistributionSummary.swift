import SwiftUI
import GymCore
import GymUI

/// Versione estesa della ripartizione: barra, elenco delle zone con percentuale e
/// composizione (quanto lavoro è diretto e quanto arriva dai muscoli secondari),
/// zone mai allenate e zone allenate solo di riflesso, nota sul metodo di calcolo.
///
/// È una view **pura**: riceve una distribuzione già calcolata e non tocca lo store,
/// così il calcolo resta fuori dal `body` (vedi ``MuscleDistributionSection``).
public struct MuscleDistributionSummary: View {

    private let distribution: Stats.MuscleDistribution
    private let title: String?
    private let showsMissingGroups: Bool

    /// - Parameters:
    ///   - distribution: quote già calcolate.
    ///   - title: intestazione; `nil` per incastonarla dove il titolo c'è già.
    ///   - showsMissingGroups: le righe "Mai allenati" e "Solo indirettamente" hanno
    ///     senso per l'intera scheda; su un singolo giorno elencherebbero mezza
    ///     anatomia (un giorno di spinta non allena le gambe: non è un difetto).
    public init(
        distribution: Stats.MuscleDistribution,
        title: String? = "Muscoli colpiti",
        showsMissingGroups: Bool = true
    ) {
        self.distribution = distribution
        self.title = title
        self.showsMissingGroups = showsMissingGroups
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let title {
                header(title)
            }

            if distribution.isEmpty {
                emptyState
            } else {
                MuscleDistributionBar(shares: distribution.shares, height: 12)
                list.padding(.top, Theme.Spacing.xs)
                footer.padding(.top, Theme.Spacing.xs)
            }
        }
    }

    // MARK: - Intestazione

    /// Intestazione leggera (overline maiuscola), come le altre sezioni della
    /// scheda: qui la ripartizione è un supporto alla lettura, non il contenuto
    /// principale della pagina.
    private func header(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).overlineStyle()

            Spacer(minLength: Theme.Spacing.m)

            if !distribution.isEmpty {
                Text(Self.setsText(distribution.totalSets))
                    .font(.captionText)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Elenco

    private var list: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(distribution.shares) { share in
                row(share)
            }
        }
    }

    /// Una riga per zona: pallino, nome, percentuale del totale pesato e, sotto in
    /// piccolo, la composizione ("4 dirette · 2 indirette").
    ///
    /// La composizione sta su una seconda riga invece che in una colonna a destra:
    /// "Quadricipiti" più la percentuale più tre numeri non ci stanno su un iPhone
    /// senza troncare o rimpicciolire, e il rimpicciolimento è rumore.
    private func row(_ share: Stats.MuscleShare) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Circle()
                .fill(MuscleGroupColor.palette(for: share.group).fill)
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(share.group.displayName)
                    .font(.system(.subheadline, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)

                Text(Self.compositionText(share))
                    .font(.system(.caption2, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: Theme.Spacing.s)

            Text("\(share.percent)%")
                .font(.system(.subheadline, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Piè di pagina

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if showsMissingGroups, !distribution.neverTrainedGroups.isEmpty {
                Text("Mai allenati: \(Self.list(distribution.neverTrainedGroups))")
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsMissingGroups, !distribution.indirectOnlyGroups.isEmpty {
                Text("Solo indirettamente: \(Self.list(distribution.indirectOnlyGroups))")
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if distribution.unresolvedItems > 0 {
                Text(Self.unresolvedText(distribution.unresolvedItems))
                    .font(.captionText)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Serie sul muscolo principale, i secondari contano la metà.")
                .font(.system(.caption2, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Stato vuoto

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            MuscleDistributionBar(shares: [], height: 12)
            Text("La ripartizione compare quando la scheda ha almeno un esercizio.")
                .font(.captionText)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Testi

    static func setsText(_ sets: Int) -> String {
        sets == 1 ? "1 serie" : "\(sets) serie"
    }

    /// "4 dirette · 2 indirette", "4 dirette", "3,5 indirette".
    ///
    /// I mezzi e i quarti si scrivono con la virgola italiana ("3,5", "0,75"): i pesi
    /// sono 1 per il principale, 0,5 per un sinergista e 0,25 per uno stabilizzatore.
    static func compositionText(_ share: Stats.MuscleShare) -> String {
        let direct = share.directSets > 0 ? "\(number(share.directSets)) \(share.directSets == 1 ? "diretta" : "dirette")" : ""
        let indirect = share.indirectSets > 0 ? "\(number(share.indirectSets)) \(share.indirectSets == 1 ? "indiretta" : "indirette")" : ""
        if direct.isEmpty { return indirect }
        if indirect.isEmpty { return direct }
        return direct + " · " + indirect
    }

    private static func number(_ value: Double) -> String {
        ItalianNumberFormat.number(value, fractionDigits: 2, grouping: false)
    }

    private static func unresolvedText(_ items: Int) -> String {
        items == 1
            ? "1 esercizio non riconosciuto, escluso dal conto."
            : "\(items) esercizi non riconosciuti, esclusi dal conto."
    }

    private static func list(_ groups: [MuscleGroup]) -> String {
        groups.map(\.displayName).joined(separator: ", ")
    }
}
