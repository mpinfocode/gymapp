import SwiftUI
import GymUI

// Una sola intestazione in tutta l'app.
//
// Prima ogni schermata aveva la sua: la Home un titolo grande minuscolo con
// l'ingranaggio nudo, Misure un'overline con la data più un titolo HEAVY MAIUSCOLO,
// Esercizi un terzo formato, la Scheda nessun titolo. Sul telefono sembravano due
// app diverse. Qui ci sono i tre soli mattoni ammessi:
//
// - ``PageHeader``  testata di una pagina (radici e pagine spinte);
// - ``SheetHeader`` testata di una sheet (titolo + azione testuale);
// - ``CircleIconButton`` / ``EllipsisMenu`` le uniche due azioni di testata.
//
// Regole: mai `pageTitleStyle` (heavy maiuscolo), mai overline con la data, al
// massimo UNA azione a destra, sempre resa allo stesso modo.

/// Testata di pagina: titolo grande, sottotitolo facoltativo e al massimo una
/// azione a destra.
///
/// Include da sé i margini (pagina 20, respiro sopra e sotto): si mette come primo
/// elemento di un `VStack(spacing: 0)`, così titolo e contenuto stanno alla stessa
/// altezza in tutte le pagine.
struct PageHeader<Trailing: View>: View {

    let title: String
    var subtitle: String?
    /// Colore del sottotitolo: serve solo alla Home, che segnala in arancio una
    /// scheda scaduta o in scadenza.
    var subtitleColor: Color = Theme.textSecondary
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .greetingStyle()
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(.captionText)
                        .foregroundStyle(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            trailing
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xl)
    }
}

extension PageHeader where Trailing == EmptyView {

    /// Testata senza azione.
    init(title: String, subtitle: String? = nil, subtitleColor: Color = Theme.textSecondary) {
        self.init(title: title, subtitle: subtitle, subtitleColor: subtitleColor) { EmptyView() }
    }
}

/// Testata di una sheet: titolo `sectionTitle` a sinistra, una sola azione testuale
/// a destra ("Fine", "Annulla", "Salva").
///
/// `back` serve alle sheet che navigano al proprio interno (il picker degli
/// esercizi): compare sopra il titolo, con lo stesso stile ovunque.
struct SheetHeader: View {

    let title: String
    var subtitle: String?
    /// Ritorno alla pagina precedente **dentro** la sheet.
    var back: (() -> Void)?
    var backTitle: String = "Indietro"
    var actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let back {
                SheetBackButton(title: backTitle, action: back)
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .sectionTitleStyle()
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    if let subtitle {
                        Text(subtitle)
                            .captionStyle()
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: Theme.Spacing.s)

                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: Theme.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text(actionTitle))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {

    /// Margini della testata di una sheet: gli stessi di ``PageHeader``, così le
    /// sheet che contengono un elenco scrollabile allineano il titolo alle pagine.
    func sheetHeaderMargins() -> some View {
        padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
    }
}

/// "Indietro" dentro una sheet: unico stile in tutta l'app.
struct SheetBackButton: View {

    var title: String = "Indietro"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "chevron.left")
                    .font(.system(.footnote, weight: .semibold))
                Text(title)
            }
            .font(.bodyText)
            .foregroundStyle(Theme.textSecondary)
            .frame(minHeight: Theme.Size.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(title))
    }
}

/// Bottone circolare da 44pt su `surface`: l'unica azione ammessa in una testata
/// di pagina ("+", ingranaggio). Non ruba la scena al titolo come una capsula `ink`.
struct CircleIconButton: View {

    let systemImage: String
    let accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(Theme.surface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(accessibilityTitle))
    }
}

/// Menu "…": stessa forma del ``CircleIconButton``, per le azioni secondarie di una
/// testata o di una riga.
struct EllipsisMenu<Content: View>: View {

    var accessibilityTitle: String = "Altre azioni"
    /// Riempimento del cerchio: bianco sopra il gradiente di una card, grigio sul
    /// fondo di pagina.
    var background: Color = Theme.surface
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(accessibilityTitle))
    }
}
