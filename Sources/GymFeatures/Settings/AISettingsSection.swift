import SwiftUI
import GymCore
import GymUI

/// Sezione "Scheda con l'AI" delle Impostazioni: stato della chiave, modello e
/// una prova facoltativa.
///
/// La chiave non compare mai: la riga di stato dice solo se c'è e le ultime
/// quattro cifre. Lo stato lo legge ``AIPreferences/refresh()`` in un `.task`,
/// così il Portachiavi non viene interrogato a ogni ridisegno.
struct AISettingsSection: View {

    @Environment(AppEnvironment.self) private var app

    @State private var isEnteringKey = false
    @State private var confirmsRemoval = false
    @State private var model = ""
    @State private var probe: ProbeState = .idle
    @FocusState private var modelFocused: Bool

    /// Esito della prova della chiave. Non porta mai il valore della chiave.
    private enum ProbeState: Equatable {
        case idle
        case running
        case ok
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Scheda con l'AI").overlineStyle()

            SettingsGroup {
                keyRow
                SettingsSeparator()
                keyActionRow
                if app.ai.status.hasKey {
                    SettingsSeparator()
                    removeRow
                }
                SettingsSeparator()
                modelRow
                if app.ai.status.hasKey {
                    SettingsSeparator()
                    probeRow
                }
            }

            shortcuts

            Text("La chiave resta solo su questo iPhone. Crea la chiave su openrouter.ai e imposta un limite di spesa.")
                .captionStyle(color: Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            app.ai.refresh()
            model = app.ai.model
        }
        .sheet(isPresented: $isEnteringKey) {
            APIKeySheet(isReplacing: app.ai.status.hasKey)
                .environment(app)
        }
        .alert("Togliere la chiave?", isPresented: $confirmsRemoval) {
            Button("Annulla", role: .cancel) {}
            Button("Rimuovi", role: .destructive) {
                _ = app.ai.removeKey()
                probe = .idle
            }
        } message: {
            Text("La scheda con l'AI userà il generatore senza AI finché non ne inserisci un'altra.")
        }
    }

    // MARK: - Chiave

    private var keyRow: some View {
        SettingsRow(title: "Chiave", value: app.ai.status.displayName)
    }

    private var keyActionRow: some View {
        SettingsActionRow(
            title: app.ai.status.hasKey ? "Sostituisci" : "Inserisci chiave",
            subtitle: app.ai.status.hasKey ? nil : "Serve solo per far proporre la scheda dall'AI.",
            action: { isEnteringKey = true }
        )
    }

    private var removeRow: some View {
        SettingsActionRow(
            title: "Rimuovi",
            tint: Theme.Metric.arancio.deep,
            action: { confirmsRemoval = true }
        )
    }

    // MARK: - Modello

    private var modelRow: some View {
        SettingsRow(title: "Modello") {
            TextField(AIPreferences.defaultModel, text: $model)
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 200)
                .textFieldStyle(.plain)
                .noAutocapitalization()
                .autocorrectionDisabled()
                .focused($modelFocused)
                .onSubmit(commitModel)
                .onChange(of: modelFocused) { _, focused in
                    if !focused { commitModel() }
                }
                .accessibilityLabel(Text("Modello OpenRouter"))
        }
    }

    /// Due o tre scorciatoie: gli stessi id del banco di prova, così si cambia
    /// modello senza digitare uno slug a memoria.
    ///
    /// Stanno **fuori** dal gruppo grigio: un chip `surface` dentro una card
    /// `surface` sparirebbe.
    private var shortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(AIPreferences.suggestedModels, id: \.self) { candidate in
                    FilterChip(shortName(candidate), isSelected: app.ai.model == candidate) {
                        modelFocused = false
                        model = candidate
                        app.ai.model = candidate
                        probe = .idle
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// "google/gemini-2.5-flash-lite" → "gemini-2.5-flash-lite".
    private func shortName(_ identifier: String) -> String {
        identifier.split(separator: "/").last.map(String.init) ?? identifier
    }

    private func commitModel() {
        let cleaned = AIPreferences.clean(model: model)
        model = cleaned
        guard cleaned != app.ai.model else { return }
        app.ai.model = cleaned
        probe = .idle
    }

    // MARK: - Prova della chiave

    @ViewBuilder
    private var probeRow: some View {
        switch probe {
        case .idle:
            SettingsActionRow(title: "Prova la chiave", action: runProbe)
        case .running:
            SettingsRow(title: "Prova la chiave", value: "In corso")
        case .ok:
            SettingsRow(title: "Prova la chiave", value: "Funziona", subtitle: "Chiave e modello sono a posto.")
        case .failed(let message):
            SettingsActionRow(
                title: "Riprova la prova",
                subtitle: message,
                tint: Theme.Metric.arancio.deep,
                action: runProbe
            )
        }
    }

    /// Una chiamata piccolissima: due parole di prompt e pochissimi token in
    /// uscita. Serve a sapere se la chiave è viva, non a generare niente.
    private func runProbe() {
        guard let key = app.ai.apiKey() else {
            probe = .failed("Non c'è nessuna chiave da provare.")
            return
        }
        let chosen = app.ai.model
        probe = .running
        Task {
            let client = OpenRouterClient(timeout: 15)
            do {
                _ = try await client.complete(
                    system: "Rispondi con la sola parola: ok.",
                    user: "ok",
                    model: chosen,
                    apiKey: key,
                    responseFormat: .jsonObject,
                    maxTokens: 16,
                    deadline: OpenRouterClient.Deadline(seconds: 15)
                )
                probe = .ok
            } catch let failure as OpenRouterClient.Failure {
                // Il messaggio arriva dal traduttore comune: non contiene la chiave.
                probe = .failed(ProgramGenerationService.translate(failure, model: chosen).message)
            } catch {
                probe = .failed("Non si riesce a contattare il servizio.")
            }
        }
    }
}
