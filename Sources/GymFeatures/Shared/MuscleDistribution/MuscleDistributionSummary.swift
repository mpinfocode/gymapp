import SwiftUI
import GymCore
import GymUI

/// Versione estesa della ripartizione: barra, elenco delle zone con percentuale e
/// serie, zone non allenate direttamente, nota sul metodo di calcolo.
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
    ///   - showsMissingGroups: la riga "Non allenati direttamente" ha senso per
    ///     l'intera scheda; su un singolo giorno elencherebbe mezza anatomia
    ///     (un giorno di spinta non allena le gambe: non è un difetto).
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

    private func row(_ share: Stats.MuscleShare) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Circle()
                .fill(MuscleGroupColor.palette(for: share.group).fill)
                .frame(width: 10, height: 10)

            Text(share.group.displayName)
                .font(.system(.subheadline, weight: .regular))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: Theme.Spacing.s)

            Text("\(share.percent)%")
                .font(.system(.subheadline, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 42, alignment: .trailing)

            Text(Self.setsText(share.sets))
                .font(.captionText)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 62, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Piè di pagina

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if showsMissingGroups, !distribution.missingGroups.isEmpty {
                Text("Non allenati direttamente: \(Self.list(distribution.missingGroups))")
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

            Text("Calcolata sulle serie e sul muscolo principale di ogni esercizio.")
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

    private static func unresolvedText(_ items: Int) -> String {
        items == 1
            ? "1 esercizio non riconosciuto, escluso dal conto."
            : "\(items) esercizi non riconosciuti, esclusi dal conto."
    }

    private static func list(_ groups: [MuscleGroup]) -> String {
        groups.map(\.displayName).joined(separator: ", ")
    }
}
