import SwiftUI
import GymCore
import GymUI

/// Attesa: una riga leggera, un indicatore di attività, una via d'uscita.
///
/// Niente gradienti animati, niente barra finta che avanza: non si sa quanto ci
/// mette, e fingere di saperlo sarebbe solo rumore (DESIGN, "senza rumore").
struct GeneratorWaitingPage: View {

    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: Theme.Spacing.xl) {
                ProgressView()
                    .controlSize(.regular)
                    .accessibilityHidden(true)

                Text("sto preparando la tua scheda")
                    .whisperStyle(color: Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Di solito ci vogliono pochi secondi.")
                    .font(.captionText)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Sto preparando la tua scheda"))

            Spacer(minLength: 0)

            GeneratorTextAction("Annulla", action: onCancel)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
    }
}

/// Nessuna chiave: due righe che spiegano a cosa serve, poi le due strade.
///
/// Non è una schermata d'errore: è una scelta. Chi non vuole dare una chiave a
/// nessuno deve poter avere comunque la sua scheda, ed è per questo che "Genera
/// senza AI" sta qui e non nascosto dietro un errore.
struct GeneratorMissingKeyPage: View {

    let onCancel: () -> Void
    let onEnterKey: () -> Void
    let onFallback: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Serve una chiave", actionTitle: "Annulla", action: onCancel)
                .sheetHeaderMargins()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("Per far proporre la scheda dall'AI serve una chiave OpenRouter, che paghi tu a consumo: la crei sul sito in un minuto.")
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("La chiave resta solo su questo iPhone, nel Portachiavi. Senza chiave la scheda si può comunque costruire, con il generatore dell'app.")
                        .font(.captionText)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.l)
            }
            .keyboardDismissable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                PrimaryButton("Inserisci la chiave", action: onEnterKey)
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.m)

                GeneratorTextAction("Genera senza AI", action: onFallback)
                    .padding(.bottom, Theme.Spacing.xs)
            }
            .background(Theme.background.ignoresSafeArea(edges: .bottom))
        }
        .pageBackground()
    }
}

/// Generazione fallita: cosa è successo e le uniche due cose utili da fare.
struct GeneratorFailurePage: View {

    let failure: ProgramGenerationFailure
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onFallback: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: failure.title, actionTitle: "Annulla", action: onCancel)
                .sheetHeaderMargins()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text(failure.message)
                        .font(.bodyText)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if failure == .invalidResponse {
                        Text("Capita con i modelli più economici. Puoi riprovare oppure prendere la scheda che costruisce l'app da sola, senza AI.")
                            .font(.captionText)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.l)
            }
            .keyboardDismissable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                primary
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.m)

                GeneratorTextAction("Genera senza AI", action: onFallback)
                    .padding(.bottom, Theme.Spacing.xs)
            }
            .background(Theme.background.ignoresSafeArea(edges: .bottom))
        }
        .pageBackground()
    }

    /// Un solo bottone primario: riprovare quando ha senso, altrimenti la strada
    /// che risolve davvero (le Impostazioni).
    @ViewBuilder
    private var primary: some View {
        if failure.allowsRetry {
            PrimaryButton("Riprova", action: onRetry)
        } else if failure.pointsToSettings {
            PrimaryButton("Apri Impostazioni", action: onOpenSettings)
        } else {
            PrimaryButton("Riprova", action: onRetry)
        }
    }
}
