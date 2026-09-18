import Foundation

/// Passo di carico **realistico** per ogni attrezzo.
///
/// In palestra non si sale di un numero qualsiasi: i dischi del bilanciere vanno
/// di 1,25 kg per lato (quindi 2,5 kg sul bilanciere), i manubri della rastrelliera
/// di 2 kg l'uno, i kettlebell di 4 kg, le piastre di cavi e macchine di 5 kg
/// (spesso 2,5 kg nella parte bassa della colonna). Proporre "21,25 kg con i
/// manubri" è un suggerimento che non si può eseguire.
///
/// A corpo libero e con gli elastici non esiste un passo: lì si progredisce
/// aggiungendo **ripetizioni** (``step(forEquipment:currentWeightKg:)`` restituisce `nil`).
///
/// Funzioni pure: la UI può usarle anche per i pulsanti +/- accanto al carico.
public enum WeightStep {

    /// Famiglia di attrezzi con lo stesso modo di caricare.
    public enum Kind: String, Sendable, Hashable, CaseIterable, Identifiable {
        /// Bilanciere, ez, trap bar, multipower: +2,5 kg (1,25 kg per lato).
        case barbell
        /// Manubri: +2 kg **per manubrio** (il carico è sempre inteso per manubrio).
        case dumbbell
        /// Kettlebell: si passa alla campana successiva, +4 kg.
        case kettlebell
        /// Cavi e macchine a pacco piastre: +5 kg, ma +2,5 kg sotto i 20 kg.
        case stack
        /// Corpo libero ed elastici: nessun passo di carico, si aggiungono ripetizioni.
        case bodyweight
        /// Attrezzi con carico libero non classificati (zavorra, palla medica…): +2,5 kg.
        case other

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .barbell: "Bilanciere"
            case .dumbbell: "Manubri"
            case .kettlebell: "Kettlebell"
            case .stack: "Cavi e macchine"
            case .bodyweight: "Corpo libero ed elastici"
            case .other: "Carico libero"
            }
        }
    }

    /// Attrezzi caricati a dischi su un bilanciere (o su una guida).
    public static let barbellEquipment: Set<String> = [
        "barbell", "olympic barbell", "ez barbell", "trap bar", "smith machine",
    ]

    /// Attrezzi senza carico regolabile: la progressione è a ripetizioni.
    public static let bodyweightEquipment: Set<String> = [
        "body weight", "band", "resistance band", "assisted", "stability ball", "bosu ball",
        "roller", "wheel roller", "rope", "tire", "elliptical machine", "stationary bike",
        "stepmill machine", "skierg machine", "upper body ergometer",
    ]

    /// Attrezzi a pacco piastre.
    public static let stackEquipment: Set<String> = [
        "cable", "leverage machine", "sled machine",
    ]

    /// Passo del pacco piastre sopra questa soglia; sotto si sale di 2,5 kg.
    public static let stackFineThresholdKg: Double = 20

    /// Famiglia di appartenenza di un attrezzo (confronto senza maiuscole né spazi).
    ///
    /// Un attrezzo sconosciuto (compresi gli esercizi personalizzati senza attrezzo)
    /// finisce in ``Kind/other``: si comporta come prima della classificazione, +2,5 kg.
    public static func kind(forEquipment equipment: String) -> Kind {
        let key = equipment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if barbellEquipment.contains(key) { return .barbell }
        if key == "dumbbell" { return .dumbbell }
        if key == "kettlebell" { return .kettlebell }
        if stackEquipment.contains(key) { return .stack }
        if bodyweightEquipment.contains(key) { return .bodyweight }
        return .other
    }

    /// Passo di carico in kg, `nil` se su quell'attrezzo il carico non si regola
    /// (corpo libero, elastici: si progredisce a ripetizioni).
    ///
    /// - Parameter currentWeightKg: carico di riferimento; serve solo ai pacchi
    ///   piastre, dove sotto i 20 kg il passo è 2,5 kg invece di 5 kg.
    public static func step(forEquipment equipment: String, currentWeightKg: Double = 0) -> Double? {
        step(for: kind(forEquipment: equipment), currentWeightKg: currentWeightKg)
    }

    /// Passo di carico di una famiglia di attrezzi.
    public static func step(for kind: Kind, currentWeightKg: Double = 0) -> Double? {
        switch kind {
        case .barbell, .other: 2.5
        case .dumbbell: 2
        case .kettlebell: 4
        case .stack: currentWeightKg < stackFineThresholdKg ? 2.5 : 5
        case .bodyweight: nil
        }
    }

    /// `true` se su quell'attrezzo conviene progredire a ripetizioni invece che a carico.
    public static func progressesByReps(forEquipment equipment: String) -> Bool {
        step(forEquipment: equipment) == nil
    }

    /// Arrotonda un carico al passo dell'attrezzo (`21,25` kg con i manubri → `22` kg).
    ///
    /// Se l'attrezzo non ha un passo il carico torna invariato.
    public static func round(_ weightKg: Double, forEquipment equipment: String) -> Double {
        guard let step = step(forEquipment: equipment, currentWeightKg: weightKg) else { return weightKg }
        return snap(weightKg, step: step)
    }

    /// Carico successivo a quello indicato, già arrotondato al passo.
    ///
    /// È il "+" della UI: restituisce `nil` sugli attrezzi senza passo di carico.
    public static func next(after weightKg: Double, forEquipment equipment: String) -> Double? {
        guard let step = step(forEquipment: equipment, currentWeightKg: weightKg) else { return nil }
        var candidate = snap(weightKg, step: step)
        while candidate <= weightKg { candidate = snap(candidate + step, step: step) }
        return candidate
    }

    /// Carico precedente a quello indicato, già arrotondato al passo.
    ///
    /// È il "−" della UI: `nil` se non c'è passo o se si andrebbe a zero o sotto.
    public static func previous(before weightKg: Double, forEquipment equipment: String) -> Double? {
        guard let step = step(forEquipment: equipment, currentWeightKg: weightKg) else { return nil }
        var candidate = snap(weightKg, step: step)
        while candidate >= weightKg { candidate = snap(candidate - step, step: step) }
        return candidate > 0 ? candidate : nil
    }

    /// Arrotondamento al multiplo del passo, ripulito dal rumore in virgola mobile.
    private static func snap(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return ((value / step).rounded() * step * 1_000).rounded() / 1_000
    }
}
