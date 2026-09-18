import GymCore
import GymUI

/// Colore stabile di ogni zona del corpo nelle ripartizioni.
///
/// La mappa è definita **una volta sola** qui: lo stesso muscolo ha lo stesso
/// colore in Home, nella Scheda e nel foglio di dettaglio, oggi e fra sei mesi.
///
/// I toni vengono tutti da ``Theme/MuscleGroupPalette`` (nessun colore letterale
/// nelle feature). L'abbinamento non è casuale: le zone che nelle schede reali
/// finiscono vicine nella barra (ordinata per quota decrescente) hanno tinte
/// lontane fra loro sulla ruota dei colori, così due segmenti adiacenti non si
/// confondono mai. Sulla scheda d'esempio Push/Pull/Legs la sequenza è
/// pesca, azzurro, rosa, lilla, menta, burro, terracotta, indaco, oliva, sabbia.
enum MuscleGroupColor {

    /// Pastello della zona: `fill` per i segmenti e i pallini, `deep` per testo e icone.
    static func palette(for group: MuscleGroup) -> AccentPalette {
        switch group {
        case .chest: Theme.MuscleGroupPalette.azzurro
        case .back: Theme.MuscleGroupPalette.pesca
        case .shoulders: Theme.MuscleGroupPalette.lilla
        case .biceps: Theme.MuscleGroupPalette.menta
        case .triceps: Theme.MuscleGroupPalette.burro
        case .quads: Theme.MuscleGroupPalette.rosa
        case .hamstrings: Theme.MuscleGroupPalette.terracotta
        case .glutes: Theme.MuscleGroupPalette.sabbia
        case .calves: Theme.MuscleGroupPalette.indaco
        case .abs: Theme.MuscleGroupPalette.oliva
        case .forearms: Theme.MuscleGroupPalette.malva
        case .cardio: Theme.MuscleGroupPalette.turchese
        case .other: Theme.MuscleGroupPalette.ardesia
        }
    }
}
