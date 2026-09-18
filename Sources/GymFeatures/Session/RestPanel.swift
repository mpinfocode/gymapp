import SwiftUI
import GymUI

/// Pannello del recupero: sta in basso, non è modale, la tabella resta usabile.
///
/// Il tempo si legge dalla data di fine del timer condiviso, quindi resta corretto
/// anche dopo un passaggio in background.
@MainActor
struct RestPanel: View {

    @Environment(AppEnvironment.self) private var app

    /// Chiamata quando il recupero arriva a zero mentre l'app è in primo piano.
    let onFinished: () -> Void

    var body: some View {
        let timer = SessionRestTimer.shared

        TimelineView(.periodic(from: app.now, by: 1)) { _ in
            let remaining = timer.remaining(asOf: app.now)

            HStack(spacing: Theme.Spacing.m) {
                RestTimerRing(
                    remaining: remaining,
                    total: timer.totalSeconds,
                    diameter: 64
                )

                Spacer(minLength: Theme.Spacing.xs)

                CircleActionButton("-15", systemImage: "gobackward.15", diameter: 52) {
                    timer.adjust(by: -15, now: app.now)
                    Haptics.play(.light)
                }
                CircleActionButton("salta", systemImage: "forward.end", diameter: 52) {
                    timer.stop()
                    Haptics.play(.light)
                }
                CircleActionButton("+15", systemImage: "goforward.15", diameter: 52) {
                    timer.adjust(by: 15, now: app.now)
                    Haptics.play(.light)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.background.opacity(0.82))
                    )
            )
            .onChange(of: remaining) { oldValue, newValue in
                guard oldValue > 0, newValue == 0 else { return }
                onFinished()
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.bottom, Theme.Spacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Recupero in corso"))
    }
}
