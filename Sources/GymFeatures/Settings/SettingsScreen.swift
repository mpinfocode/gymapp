import SwiftUI
import GymCore
import GymUI

/// Impostazioni (SPEC §5.6): nome, unità, recupero di default, vibrazione, media
/// offline, crediti e licenze.
///
/// Si apre come **sheet** da ``TodayScreen``, non è un tab. Niente backup, niente
/// lingua: l'app è in italiano e i dati restano sul telefono.
public struct SettingsScreen: View {

    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var media = MediaDownloadModel()
    @State private var name = ""
    @State private var showsClearConfirmation = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                header
                sampleProgram
                preferences
                offlineMedia
                about
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .pageBackground()
        .task {
            name = app.store.settings.displayName
            await media.refreshSize()
        }
        .onDisappear { media.cancel() }
        .alert("Svuotare la cache?", isPresented: $showsClearConfirmation) {
            Button("Annulla", role: .cancel) {}
            Button("Svuota", role: .destructive) {
                Task { await media.clearCache() }
            }
        } message: {
            Text("Le immagini e le GIF verranno riscaricate quando servono.")
        }
    }

    // MARK: - Intestazione

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Text("Impostazioni")
                .greetingStyle()
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Theme.Spacing.s)

            Button {
                dismiss()
            } label: {
                Text("Fine")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: Theme.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Chiudi le impostazioni"))
        }
    }

    // MARK: - Preferenze

    private var preferences: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Preferenze")
                .overlineStyle()

            SettingsGroup {
                SettingsRow(title: "Nome") {
                    TextField("il tuo nome", text: $name)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 170)
                        .plainTextField()
                        .onChange(of: name) { _, value in
                            app.store.updateSettings { $0.displayName = value }
                        }
                        .accessibilityLabel(Text("Nome"))
                }

                SettingsSeparator()

                SettingsRow(title: "Unità") {
                    CapsuleSegmentedControl(values: WeightUnit.allCases, selection: unitBinding)
                        .frame(width: 128)
                        .accessibilityLabel(Text("Unità di misura"))
                }

                SettingsSeparator()

                SettingsRow(title: "Recupero predefinito") {
                    SettingsStepper(
                        value: Formatters.shortDuration(seconds: app.store.settings.defaultRestSeconds),
                        canDecrease: app.store.settings.defaultRestSeconds > 15,
                        canIncrease: app.store.settings.defaultRestSeconds < 600,
                        decreaseLabel: "Riduci di 15 secondi",
                        increaseLabel: "Aumenta di 15 secondi",
                        onDecrease: { changeRest(by: -15) },
                        onIncrease: { changeRest(by: 15) }
                    )
                }

                SettingsSeparator()

                SettingsRow(title: "Vibrazione") {
                    Toggle("Vibrazione", isOn: hapticsBinding)
                        .labelsHidden()
                        .tint(Theme.accent.deep)
                }
            }
        }
    }

    private var unitBinding: Binding<WeightUnit> {
        Binding(
            get: { app.store.settings.unit },
            set: { value in app.store.updateSettings { $0.unit = value } }
        )
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { app.store.settings.hapticsEnabled },
            set: { value in app.store.updateSettings { $0.hapticsEnabled = value } }
        )
    }

    private func changeRest(by delta: Int) {
        app.store.updateSettings {
            $0.defaultRestSeconds = min(600, max(15, $0.defaultRestSeconds + delta))
        }
    }

    // MARK: - Media offline

    private var offlineMedia: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Media offline")
                .overlineStyle()

            SettingsGroup {
                SettingsRow(title: "Spazio occupato", value: media.cacheSizeText)

                SettingsSeparator()

                if media.isRunning {
                    downloadProgress
                } else {
                    SettingsActionRow(
                        title: "Scarica tutte le GIF",
                        subtitle: media.progressText ?? "In palestra la rete spesso non c'è.",
                        action: { media.start(urls: mediaURLs) }
                    )
                }

                SettingsSeparator()

                SettingsActionRow(
                    title: "Svuota cache",
                    tint: Theme.Metric.arancio.deep,
                    action: { showsClearConfirmation = true }
                )
            }
        }
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scaricamento in corso")
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                    if let progressText = media.progressText {
                        Text(progressText)
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }

                Spacer(minLength: Theme.Spacing.s)

                Button {
                    media.cancel()
                } label: {
                    Text("Annulla")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: Theme.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Annulla il download"))
            }

            ThickProgressBar(
                value: media.fraction,
                total: 1,
                height: 6,
                tint: Theme.ink,
                accessibilityTitle: "Avanzamento del download"
            )
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
    }

    /// Tutte le immagini e le GIF della libreria, senza duplicati.
    private var mediaURLs: [URL] {
        guard let exercises = app.store.exercises else { return [] }
        var seen: Set<URL> = []
        var urls: [URL] = []
        for exercise in exercises.all {
            for url in [exercise.gifURL, exercise.imageURL].compactMap({ $0 }) where seen.insert(url).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    // MARK: - Informazioni

    private var about: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Informazioni")
                .overlineStyle()

            SettingsGroup {
                SettingsRow(title: "Versione", value: Self.appVersion)
                SettingsSeparator()
                SettingsRow(title: "Dati esercizi", value: "MIT, Hasan Emir Yıldırım")
                SettingsSeparator()
                SettingsRow(title: "Media", value: "© Gym visual")
            }

            Text("I media degli esercizi sono di Gym visual e vengono usati con attribuzione.")
                .captionStyle(color: Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(Exercise.displayAttribution)
                .captionStyle(color: Theme.textTertiary)
                .textSelection(.enabled)
        }
    }

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }

    // MARK: - Scheda d'esempio

    @ViewBuilder
    private var sampleProgram: some View {
        if app.store.programs.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Per iniziare")
                    .overlineStyle()

                SettingsGroup {
                    SettingsActionRow(
                        title: "Carica scheda d'esempio",
                        subtitle: "Push, Pull e Legs su tre giorni: un punto di partenza da modificare.",
                        action: {
                            app.store.loadSampleProgram()
                            app.router.tab = .program
                            dismiss()
                        }
                    )
                }
            }
        }
    }
}

private extension View {

    /// `TextField` senza decorazioni: lo stile `.plain` esiste su iOS e macOS ma
    /// il nome del tipo non è condiviso, quindi resta isolato qui.
    @ViewBuilder
    func plainTextField() -> some View {
        #if os(iOS)
        self.textFieldStyle(.plain)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
        #else
        self.textFieldStyle(.plain)
        #endif
    }
}
