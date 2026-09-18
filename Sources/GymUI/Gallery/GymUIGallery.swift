import SwiftUI

/// Vetrina di tutti i componenti di `GymUI`, per il controllo visivo.
///
/// Non fa parte delle schermate dell'app: si monta temporaneamente al posto della root
/// (o dietro un'opzione di debug) per verificare tema chiaro, tema scuro e Dynamic Type.
public struct GymUIGallery: View {

    /// Tab d'esempio della `FloatingTabBar`.
    private enum DemoTab: String, Hashable, Sendable, CaseIterable {
        case oggi, esercizi, schede, progressi
    }

    /// Range d'esempio del segmented control.
    private enum DemoRange: String, Hashable, CaseIterable {
        case m1 = "1M"
        case m3 = "3M"
        case m6 = "6M"
        case y1 = "1A"
    }

    @State private var tab: DemoTab = .oggi
    @State private var range: DemoRange = .m3
    @State private var search = ""
    @State private var selectedFilters: Set<String> = ["Petto"]
    @State private var setDone = false
    @State private var weight: Double? = 62.5
    @State private var reps: Int?
    @State private var remaining = 74

    /// URL reale del dataset, per verificare cache, GIF e thumbnail su dispositivo.
    private let sampleGIF = URL(string: "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/videos/0025-EIeI8Vf.gif")
    private let sampleImage = URL(string: "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/images/0025-EIeI8Vf.jpg")

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            PageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    typographySection
                    heroSection
                    buttonsSection
                    rowsSection
                    controlsSection
                    weekSection
                    metricsSection
                    sessionSection
                    mediaSection
                    emptySection
                    gradientsSection
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, 140)
            }

            FloatingTabBar(
                items: DemoTab.allCases.map {
                    TabItem(id: $0, title: $0.rawValue.capitalized, systemImage: icon(for: $0))
                },
                selection: $tab
            )
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.l)
        }
    }

    // MARK: - Sezioni

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("venerdì 18 settembre").overlineStyle()
            Text("Buongiorno, Francesco").greetingStyle()
            Text("Progressi").pageTitleStyle()
            Text("Questa settimana").sectionTitleStyle()
            Text("pronto per iniziare?").whisperStyle()
            Text("12.480").bigNumberStyle()
            Text("Corpo del testo su due righe, per verificare interlinea e colore secondario.")
                .font(.bodyText)
                .foregroundStyle(Theme.textSecondary)
            Text("Didascalia").captionStyle()
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            SectionHeader("Hero", actionTitle: "Vedi tutto") {}
            HeroCard(seed: 2, chipText: "oggi", chipSystemImage: "flame") { palette in
                Text("Push A")
                    .font(.system(.largeTitle, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                Text("45 min · 6 esercizi")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(palette.foreground.opacity(0.85))
            }
        }
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Bottoni")
            PrimaryButton("Inizia allenamento", systemImage: "play.fill") {}
            PrimaryButton("Termina", variant: .accent) {}
            HStack(spacing: Theme.Spacing.m) {
                PillButton("Modifica piano", systemImage: "slider.horizontal.3") {}
                PillButton("Vedi storico", systemImage: "clock.arrow.circlepath") {}
            }
            HStack(spacing: Theme.Spacing.xxl) {
                CircleActionButton("-15s", text: "-15") {}
                CircleActionButton("salta", systemImage: "forward.fill") {}
                CircleActionButton("+15s", text: "+15") {}
                Spacer()
                FloatingPlusButton(accessibilityTitle: "Aggiungi esercizio") {}
            }
        }
    }

    private var rowsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Righe")
            PillRow(
                title: "Panca piana",
                subtitle: "4 × 8 · 90 s",
                detail: "80 kg",
                systemImage: "figure.strengthtraining.traditional",
                action: {}
            )
            PillRow(title: "Recupero predefinito", detail: "90 s", systemImage: "timer", action: {})
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Controlli")
            SearchField(placeholder: "Cerca un esercizio", text: $search)
            CapsuleSegmentedControl(values: DemoRange.allCases, selection: $range)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(["Petto", "Dorso", "Gambe", "Preferiti"], id: \.self) { name in
                        FilterChip(name, count: 42, isSelected: selectedFilters.contains(name)) {
                            if selectedFilters.contains(name) {
                                selectedFilters.remove(name)
                            } else {
                                selectedFilters.insert(name)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            ThickProgressBar(value: 3, total: 4, accessibilityTitle: "Allenamenti della settimana")
        }
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Settimana")
            Card {
                WeekStrip(days: Self.sampleWeek)
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Costanza").overlineStyle()
                    HabitGrid(values: Self.sampleHabits, columns: 10)
                }
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Dashboard", action: {})
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.m),
                    GridItem(.flexible(), spacing: Theme.Spacing.m),
                ],
                spacing: Theme.Spacing.m
            ) {
                MetricCard(
                    title: "Peso corporeo",
                    subtitle: "Ultimi 7 giorni",
                    value: "78,4",
                    unit: "kg",
                    tint: Theme.Metric.viola,
                    action: {}
                ) {
                    Sparkline(values: [79.2, 79.0, 78.9, 78.6, 78.8, 78.5, 78.4], tint: Theme.Metric.viola)
                }
                MetricCard(
                    title: "Volume",
                    subtitle: "Ultime 6 settimane",
                    value: "12.480",
                    unit: "kg",
                    tint: Theme.Metric.arancio,
                    action: {}
                ) {
                    MiniBars(values: [8, 11, 9, 13, 12, 14], tint: Theme.Metric.arancio, highlightedIndex: 5)
                }
                MetricCard(
                    title: "Costanza",
                    subtitle: "Ultimi 30 giorni",
                    value: "18",
                    unit: "giorni",
                    tint: Theme.Metric.verde,
                    action: {}
                ) {
                    HabitGrid(values: Self.sampleHabits, columns: 10, tint: Theme.Metric.verde, squareSide: 9)
                }
                MetricCard(
                    title: "Allenamenti",
                    subtitle: "Questa settimana",
                    value: "3",
                    unit: "su 4",
                    tint: Theme.Metric.blu
                ) {
                    MiniBars(values: [2, 3, 4, 3, 4, 3], tint: Theme.Metric.blu)
                }
            }
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Sessione (scuro immersivo)")
            VStack(spacing: Theme.Spacing.xl) {
                RestTimerRing(remaining: remaining, total: 90, diameter: 180, caption: "recupera")
                HStack(spacing: Theme.Spacing.m) {
                    Text("SERIE 3").overlineStyle()
                    Spacer()
                    NumberCapsuleField(value: $weight, placeholder: "80", accessibilityTitle: "Chilogrammi, serie 3")
                    NumberCapsuleField(value: $reps, placeholder: "8", accessibilityTitle: "Ripetizioni, serie 3")
                    SetCheckButton(isCompleted: $setDone, accessibilityTitle: "Completa la serie 3")
                }
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .fill(Theme.background)
            }
            .immersiveDark()
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Media")
            HStack(alignment: .top, spacing: Theme.Spacing.l) {
                AnimatedGIFView(url: sampleGIF, side: 180, accessibilityTitle: "Dimostrazione dell'esercizio")
                VStack(spacing: Theme.Spacing.m) {
                    RemoteImage(url: sampleImage, side: 64)
                    RemoteImage(url: nil, side: 64)
                }
            }
        }
    }

    private var emptySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Stato vuoto")
            Card {
                EmptyStateView(
                    systemImage: "tray",
                    title: "Nessuna scheda",
                    message: "Crea la tua prima scheda per iniziare ad allenarti.",
                    actionTitle: "Crea una scheda",
                    action: {}
                )
            }
        }
    }

    private var gradientsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Gradienti (8 seed)")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.m),
                    GridItem(.flexible(), spacing: Theme.Spacing.m),
                ],
                spacing: Theme.Spacing.m
            ) {
                ForEach(BlobPalette.all) { palette in
                    ZStack(alignment: .bottomLeading) {
                        BlobGradient(seed: palette.id)
                        Text(palette.name)
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(palette.foreground)
                            .padding(Theme.Spacing.m)
                    }
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                }
            }
        }
    }

    // MARK: - Dati d'esempio

    private func icon(for tab: DemoTab) -> String {
        switch tab {
        case .oggi: "sun.max"
        case .esercizi: "figure.strengthtraining.traditional"
        case .schede: "square.stack"
        case .progressi: "chart.line.uptrend.xyaxis"
        }
    }

    private static let sampleWeek: [WeekDayItem] = [
        WeekDayItem(id: 0, initial: "L", fullName: "lunedì", dayNumber: 15, state: .completed, isToday: false),
        WeekDayItem(id: 1, initial: "M", fullName: "martedì", dayNumber: 16, state: .rest, isToday: false),
        WeekDayItem(id: 2, initial: "M", fullName: "mercoledì", dayNumber: 17, state: .completed, isToday: false),
        WeekDayItem(id: 3, initial: "G", fullName: "giovedì", dayNumber: 18, state: .planned, isToday: true),
        WeekDayItem(id: 4, initial: "V", fullName: "venerdì", dayNumber: 19, state: .planned, isToday: false),
        WeekDayItem(id: 5, initial: "S", fullName: "sabato", dayNumber: 20, state: .rest, isToday: false),
        WeekDayItem(id: 6, initial: "D", fullName: "domenica", dayNumber: 21, state: .planned, isToday: false),
    ]

    private static let sampleHabits: [Double] = (0..<30).map { index in
        [0, 1, 0.6, 0, 1, 1, 0][index % 7]
    }
}
