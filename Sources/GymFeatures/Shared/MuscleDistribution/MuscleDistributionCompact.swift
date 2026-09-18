import SwiftUI
import GymCore
import GymUI

/// Versione compatta per la Home: la barra del giorno scelto e una riga con le
/// prime tre zone. Toccandola si apre il dettaglio a mezza altezza, dove si può
/// passare da "Tutta la scheda" a "Questo giorno".
///
/// La Home resta una schermata da palestra: qui non c'è titolo, non c'è card, non
/// c'è elenco. Due righe in tutto, sotto l'intestazione.
public struct MuscleDistributionCompact: View {

    private let programID: UUID
    private let dayID: UUID?

    @Environment(AppEnvironment.self) private var app
    @State private var dayDistribution: Stats.MuscleDistribution?
    @State private var programDistribution: Stats.MuscleDistribution?
    @State private var isDetailPresented = false
    @State private var scope: Scope = .day

    /// Ambito mostrato nel foglio di dettaglio.
    private enum Scope: Hashable, CaseIterable {
        case program
        case day

        var displayName: String {
            switch self {
            case .program: "Tutta la scheda"
            case .day: "Questo giorno"
            }
        }
    }

    /// - Parameters:
    ///   - programID: scheda attiva.
    ///   - dayID: giorno selezionato in Home; `nil` mostra l'intera scheda.
    public init(programID: UUID, dayID: UUID?) {
        self.programID = programID
        self.dayID = dayID
    }

    public var body: some View {
        let signature = app.muscleDistributionSignature(programID: programID, dayID: dayID)
        // Il contenuto può essere vuoto (scheda senza esercizi): il contenitore deve
        // esistere comunque, altrimenti il `.task` non parte mai.
        return VStack(alignment: .leading, spacing: 0) { content }
            .task(id: signature) {
                dayDistribution = app.muscleDistribution(for: signature)
                programDistribution = app.muscleDistribution(
                    for: MuscleDistributionSignature(
                        programID: signature.programID,
                        dayID: nil,
                        updatedAt: signature.updatedAt,
                        libraryReady: signature.libraryReady
                    )
                )
            }
            .sheet(isPresented: $isDetailPresented) { detail }
    }

    @ViewBuilder
    private var content: some View {
        if let dayDistribution, !dayDistribution.isEmpty {
            Button {
                scope = dayID == nil ? .program : .day
                isDetailPresented = true
            } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    MuscleDistributionBar(shares: dayDistribution.shares, height: 10)
                    Text(Self.topLine(dayDistribution))
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(minHeight: Theme.Size.minTapTarget, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Muscoli colpiti")
            .accessibilityValue(Self.topLine(dayDistribution))
            .accessibilityHint("Apre la ripartizione completa")
        }
    }

    // MARK: - Foglio di dettaglio

    private var detail: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    CapsuleSegmentedControl(
                        values: Scope.allCases,
                        selection: $scope,
                        title: \.displayName
                    )

                    MuscleDistributionSummary(
                        distribution: shownDistribution,
                        title: nil,
                        showsMissingGroups: scope == .program
                    )
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .pageBackground()
            .navigationTitle("Muscoli colpiti")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { isDetailPresented = false }
                }
            }
        }
        .mediumDetentSheet()
    }

    private var shownDistribution: Stats.MuscleDistribution {
        switch scope {
        case .program: programDistribution ?? .empty
        case .day: dayDistribution ?? .empty
        }
    }

    // MARK: - Testi

    /// "Petto 37% · Spalle 32% · Tricipiti 31%"
    static func topLine(_ distribution: Stats.MuscleDistribution, count: Int = 3) -> String {
        distribution.topShares(count)
            .map { "\($0.group.displayName) \($0.percent)%" }
            .joined(separator: " · ")
    }
}

extension View {

    /// Foglio a mezza altezza: i detent esistono solo su iOS, su macOS (screenshot)
    /// resta la sheet standard.
    @ViewBuilder
    func mediumDetentSheet() -> some View {
        #if os(iOS)
        self.presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        #else
        self
        #endif
    }
}
