#if os(macOS)
import SwiftUI
import GymFeatures

/// Lo schermo dell'iPhone simulato: ``RootView`` dentro una cornice arrotondata,
/// con le stesse safe area del dispositivo scelto.
///
/// ## Due modi di passare le safe area, e perché ne serviva un secondo
///
/// - **morbida** (`rigidSafeArea == false`): la cornice usa `safeAreaInset`, che è
///   il meccanismo con cui iOS riserva barra di stato e home indicator. La vista
///   inserita occupa il bordo e **riduce la safe area** del contenuto. Comodo, ma
///   proprio questa riduzione sul telefono vero **non si propaga** dentro i
///   `NavigationStack` e le `ScrollView`: l'anteprima sembrava corretta mentre
///   l'app su iPhone aveva l'ultima riga sotto il menu e il contenuto sotto
///   l'orologio. In altre parole: questa modalità NASCONDE proprio la classe di
///   difetti da cercare.
/// - **rigida** (predefinita): la cornice non passa **nessuna** safe area al
///   contenuto e comunica le misure alla shell con
///   ``EnvironmentValues/deviceInsetsOverride``. La shell costruisce le sue fasce
///   da quei numeri, esattamente come sul telefono le costruisce dalla safe area
///   della finestra, e tutto ciò che sta sotto la shell (stack, liste, pagine
///   spinte) vive con safe area zero, come accade davvero su iPhone.
struct DeviceFrameView: View {

    let device: PreviewDevice
    let environment: AppEnvironment?
    let dark: Bool
    /// `true` (predefinito): nessuna safe area al contenuto, misure passate a mano.
    var rigidSafeArea: Bool = true

    /// Margine neutro attorno alla cornice.
    static let margin: CGFloat = 20

    /// Dimensione della finestra per un dispositivo.
    static func windowSize(for device: PreviewDevice) -> CGSize {
        CGSize(width: device.size.width + margin * 2, height: device.size.height + margin * 2)
    }

    var body: some View {
        screen
            .frame(width: device.size.width, height: device.size.height)
            .clipShape(RoundedRectangle(cornerRadius: device.cornerRadius, style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
            .padding(Self.margin)
            .frame(
                width: Self.windowSize(for: device).width,
                height: Self.windowSize(for: device).height
            )
            .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private var screen: some View {
        if let environment {
            if rigidSafeArea {
                // Nessuna safe area: la shell riceve solo le misure e si costruisce
                // le fasce da sé. Barra di stato e home indicator sono disegnati
                // SOPRA, come fa il vetro del telefono: non tolgono spazio a
                // nessuno e non riducono nessuna safe area.
                RootView(environment: environment)
                    .environment(\.deviceInsetsOverride, DeviceInsets(
                        top: device.topInset,
                        bottom: device.bottomInset
                    ))
                    .overlay(alignment: .top) {
                        StatusBarView(height: device.topInset, compact: device.bottomInset == 0)
                    }
                    .overlay(alignment: .bottom) {
                        HomeIndicatorView(height: device.bottomInset)
                    }
            } else {
                RootView(environment: environment)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        StatusBarView(height: device.topInset, compact: device.bottomInset == 0)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HomeIndicatorView(height: device.bottomInset)
                    }
            }
        } else {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                Text("Caricamento")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Finta barra di stato: ora corrente a sinistra, indicatori a destra.
///
/// Non prova a imitare il pixel di iOS: serve a occupare lo spazio giusto e a
/// rendere riconoscibile che quella zona non è disponibile al contenuto.
private struct StatusBarView: View {

    let height: CGFloat
    /// Dispositivi senza notch: barra bassa, tutto su una riga sottile.
    let compact: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                Text(Self.formatter.string(from: context.date))
                    .font(.system(size: compact ? 12 : 15, weight: .semibold))
                Spacer(minLength: 8)
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
            }
            .font(.system(size: compact ? 11 : 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, compact ? 12 : 26)
            .frame(height: height, alignment: compact ? .center : .bottom)
            .padding(.bottom, compact ? 0 : 4)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.setLocalizedDateFormatFromTemplate("Hm")
        return formatter
    }()
}

/// Finto home indicator: la barretta in fondo allo schermo.
private struct HomeIndicatorView: View {

    let height: CGFloat

    var body: some View {
        if height > 0 {
            Capsule(style: .continuous)
                .fill(.primary)
                .frame(width: 140, height: 5)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: height, alignment: .bottom)
                .accessibilityHidden(true)
        }
    }
}
#endif
