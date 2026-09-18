import Foundation

/// Un esercizio della libreria (dataset `exercises-dataset`, 1.324 record).
///
/// I nomi del dataset sono solo in inglese e vanno mostrati tramite ``displayName``.
/// Categoria, attrezzo e muscoli si traducono con ``Localization``.
public struct Exercise: Codable, Sendable, Hashable, Identifiable {

    /// Prefisso remoto dei media (immagini e GIF). Vedi SPEC §2.
    public static let mediaBaseURL = URL(string: "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/")!

    /// Identificatore del dataset (stringa numerica con zeri iniziali, es. `"0025"`).
    public let id: String
    /// Nome inglese così come compare nel dataset (minuscolo).
    public let name: String
    /// Una delle 10 categorie del dataset (`chest`, `back`, …), in inglese.
    public let category: String
    /// Distretto corporeo; nel dataset corrente coincide sempre con ``category``.
    public let bodyPart: String
    /// Uno dei 28 attrezzi del dataset, in inglese.
    public let equipment: String
    /// Muscolo bersaglio principale, in inglese.
    ///
    /// Per gli esercizi della libreria è il valore **corretto** da ``ExerciseCorrections``
    /// (il JSON su disco resta quello upstream).
    public let target: String
    /// - Warning: **Campo inaffidabile, non usarlo.** Nel dataset `muscle_group` è
    ///   una copia del primo muscolo secondario su tutti e 1.324 i record (SPEC §2,
    ///   punto 2). Resta pubblico solo per compatibilità e per il round-trip Codable:
    ///   ricerca, filtri, facet e statistiche lo ignorano completamente.
    ///   Per la zona colpita usa ``muscleGroupKind``; per il muscolo usa ``target``.
    ///
    ///   Non è marcato `@available(deprecated)` di proposito: farebbe scattare un
    ///   warning anche nel round-trip Codable e nel codice che sta nascendo in
    ///   parallelo, e la regola di progetto è "zero warning" (SPEC §6).
    public let muscleGroup: String
    /// Muscoli secondari coinvolti, in inglese.
    public let secondaryMuscles: [String]
    /// Istruzioni passo-passo in italiano (con fallback all'inglese se l'italiano manca).
    public let steps: [String]
    /// Percorso relativo dell'immagine statica, es. `images/0025-xxxx.jpg`.
    public let imagePath: String
    /// Percorso relativo della GIF animata, es. `videos/0025-xxxx.gif`.
    public let gifPath: String
    /// Attribuzione dei media così com'è nel dataset; per la UI usa ``displayAttribution``.
    public let attribution: String
    /// Nota libera dell'utente. Valorizzata solo dagli esercizi personalizzati.
    public let notes: String
    /// `true` se è un esercizio creato dall'utente (SPEC §2, punto 5).
    ///
    /// Gli esercizi personalizzati hanno id `custom-<uuid>`, nessuna GIF e nessuna
    /// immagine; il flag resta vero anche se l'id venisse cambiato a mano.
    public let isCustom: Bool
    /// `true` se l'utente ha eliminato un esercizio personalizzato che però è citato
    /// da una scheda o da una sessione.
    ///
    /// Soft delete: il record resta nello store con nome e dati, così lo **storico
    /// non si rompe**; sparisce solo da ricerca, filtri e facet.
    public let isDeleted: Bool

    public init(
        id: String,
        name: String,
        category: String = "",
        bodyPart: String = "",
        equipment: String = "",
        target: String = "",
        muscleGroup: String = "",
        secondaryMuscles: [String] = [],
        steps: [String] = [],
        imagePath: String = "",
        gifPath: String = "",
        attribution: String = Exercise.defaultAttribution,
        notes: String = "",
        isCustom: Bool = false,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        // Come nella decodifica: un distretto vuoto ricade sulla categoria,
        // così il round-trip Codable è stabile.
        self.bodyPart = bodyPart.isEmpty ? category : bodyPart
        self.equipment = equipment
        self.target = target
        self.muscleGroup = muscleGroup
        self.secondaryMuscles = secondaryMuscles
        self.steps = steps
        self.imagePath = imagePath
        self.gifPath = gifPath
        self.attribution = attribution
        self.notes = notes
        self.isCustom = isCustom || id.hasPrefix(Exercise.customIDPrefix)
        self.isDeleted = isDeleted
    }

    /// Attribuzione da mostrare nella UI (dettaglio esercizio, Impostazioni, Crediti).
    ///
    /// Il campo `attribution` del dataset resta decodificato così com'è; questa è la
    /// forma di presentazione.
    public static let displayAttribution = "© Gym visual · https://gymvisual.com/"

    /// Attribuzione usata quando il record del dataset non ne porta una.
    public static let defaultAttribution = displayAttribution

    // MARK: - Esercizi personalizzati

    /// Prefisso degli id creati dall'utente (SPEC §2, punto 5).
    public static let customIDPrefix = "custom-"

    /// Id nuovo per un esercizio personalizzato (`custom-<uuid>`).
    public static func makeCustomID() -> String { "\(customIDPrefix)\(UUID().uuidString.lowercased())" }

    /// Crea un esercizio personalizzato: niente media, niente attribuzione Gym visual.
    ///
    /// - Parameters:
    ///   - id: lasciarlo `nil` genera un `custom-<uuid>` nuovo.
    ///   - category: una delle categorie del dataset (`upper legs`, `chest`, …) oppure
    ///     stringa vuota; serve solo a far ricadere l'esercizio nei filtri per zona.
    ///   - target: muscolo bersaglio in inglese, così le statistiche per gruppo
    ///     muscolare lo sanno collocare (vedi ``MuscleGroup``).
    public static func custom(
        id: String? = nil,
        name: String,
        category: String = "",
        equipment: String = "",
        target: String = "",
        secondaryMuscles: [String] = [],
        notes: String = "",
        isDeleted: Bool = false
    ) -> Exercise {
        Exercise(
            id: id ?? makeCustomID(),
            name: name,
            category: category,
            bodyPart: category,
            equipment: equipment,
            target: target,
            muscleGroup: "",
            secondaryMuscles: secondaryMuscles,
            steps: [],
            imagePath: "",
            gifPath: "",
            attribution: "",
            notes: notes,
            isCustom: true,
            isDeleted: isDeleted
        )
    }

    // MARK: - Varianti ridondanti

    /// `true` per le varianti ridondanti del dataset: `"… v. 2"`, `"(male)"`,
    /// `"(female)"`, `"(back pov)"`, `"(side pov)"` (SPEC §2, punto 4).
    ///
    /// Restano in libreria, ma nella ricerca, **a parità di punteggio**, finiscono
    /// dopo la variante base.
    public var isRedundantVariant: Bool { Exercise.isRedundantVariantName(name) }

    /// Riconosce il nome di una variante ridondante.
    ///
    /// Lavora sul nome **normalizzato**, dove la punteggiatura è già sparita:
    /// `"barbell rear lunge v. 2"` → `["barbell","rear","lunge","v","2"]`,
    /// `"barbell full squat (back pov)"` → `[…,"back","pov"]`.
    public static func isRedundantVariantName(_ name: String) -> Bool {
        isRedundantVariant(nameTokens: SearchText.tokens(name))
    }

    static func isRedundantVariant(nameTokens tokens: [String]) -> Bool {
        for (position, token) in tokens.enumerated() {
            if token == "male" || token == "female" || token == "pov" { return true }
            if token == "v", position + 1 < tokens.count, tokens[position + 1].allSatisfy(\.isNumber) { return true }
        }
        return false
    }

    /// `true` se l'esercizio è utilizzabile in ricerca, filtri e picker.
    ///
    /// Un personalizzato eliminato ma ancora citato dallo storico resta risolvibile
    /// per id, però non deve più comparire nelle liste.
    public var isSelectable: Bool { !isDeleted }

    // MARK: - Copie

    /// Copia con target e secondari sostituiti (usata da ``ExerciseCorrections``).
    public func replacingMuscles(target: String, secondaryMuscles: [String]) -> Exercise {
        Exercise(
            id: id,
            name: name,
            category: category,
            bodyPart: bodyPart,
            equipment: equipment,
            target: target,
            muscleGroup: muscleGroup,
            secondaryMuscles: secondaryMuscles,
            steps: steps,
            imagePath: imagePath,
            gifPath: gifPath,
            attribution: attribution,
            notes: notes,
            isCustom: isCustom,
            isDeleted: isDeleted
        )
    }

    /// Copia con il flag di soft delete cambiato.
    public func markingDeleted(_ deleted: Bool) -> Exercise {
        Exercise(
            id: id,
            name: name,
            category: category,
            bodyPart: bodyPart,
            equipment: equipment,
            target: target,
            muscleGroup: muscleGroup,
            secondaryMuscles: secondaryMuscles,
            steps: steps,
            imagePath: imagePath,
            gifPath: gifPath,
            attribution: attribution,
            notes: notes,
            isCustom: isCustom,
            isDeleted: deleted
        )
    }

    // MARK: - Helper di presentazione

    /// Nome con l'iniziale di ogni parola maiuscola (`"barbell bench press"` → `"Barbell Bench Press"`).
    ///
    /// Non usa `String.capitalized` per non alterare il resto della parola
    /// (`"3/4 sit-up"` → `"3/4 Sit-up"`, non `"3/4 Sit-Up"`).
    public var displayName: String { Exercise.capitalizingWords(name) }

    /// URL assoluto dell'immagine statica, `nil` se il dataset non la fornisce.
    public var imageURL: URL? { Exercise.mediaURL(for: imagePath) }

    /// URL assoluto della GIF animata, `nil` se il dataset non la fornisce.
    public var gifURL: URL? { Exercise.mediaURL(for: gifPath) }

    /// Categoria tradotta in italiano.
    public var localizedCategory: String { Localization.category(category) }
    /// Attrezzo tradotto in italiano.
    public var localizedEquipment: String { Localization.equipment(equipment) }
    /// Muscolo bersaglio tradotto in italiano.
    public var localizedTarget: String { Localization.muscle(target) }
    /// Traduzione italiana di ``muscleGroup``.
    /// - Warning: **Non mostrarla nella UI**: `muscle_group` è un campo inaffidabile
    ///   del dataset. Per la zona colpita usa ``localizedMuscleGroupKind``.
    public var localizedMuscleGroup: String { Localization.muscle(muscleGroup) }
    /// Muscoli secondari tradotti in italiano, senza duplicati e nell'ordine originale.
    public var localizedSecondaryMuscles: [String] { Localization.muscles(secondaryMuscles) }

    static func mediaURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed, relativeTo: mediaBaseURL)?.absoluteURL
    }

    static func capitalizingWords(_ value: String) -> String {
        value
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case bodyPart = "body_part"
        case equipment
        case target
        case muscleGroup = "muscle_group"
        case secondaryMuscles = "secondary_muscles"
        case instructionSteps = "instruction_steps"
        case imagePath = "image"
        case gifPath = "gif_url"
        case attribution
        case notes
        case isCustom = "is_custom"
        case isDeleted = "is_deleted"
    }

    /// Chiave della lingua usata nel dataset per le istruzioni.
    private static let italianKey = "it"
    private static let englishKey = "en"

    /// Decodifica tollerante: solo `id` e `name` sono obbligatori, ogni altro campo
    /// assente o `null` ricade sul proprio default. Serve a sopravvivere a evoluzioni
    /// dello schema del dataset senza rompere l'app installata.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        equipment = try container.decodeIfPresent(String.self, forKey: .equipment) ?? ""
        target = try container.decodeIfPresent(String.self, forKey: .target) ?? ""
        muscleGroup = try container.decodeIfPresent(String.self, forKey: .muscleGroup) ?? ""
        secondaryMuscles = try container.decodeIfPresent([String].self, forKey: .secondaryMuscles) ?? []
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath) ?? ""
        gifPath = try container.decodeIfPresent(String.self, forKey: .gifPath) ?? ""
        attribution = try container.decodeIfPresent(String.self, forKey: .attribution) ?? Exercise.defaultAttribution
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        let decodedCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        isCustom = decodedCustom || id.hasPrefix(Exercise.customIDPrefix)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        // `body_part` manca in alcune varianti del dataset: ricade sulla categoria.
        let decodedBodyPart = try container.decodeIfPresent(String.self, forKey: .bodyPart)
        bodyPart = (decodedBodyPart?.isEmpty == false) ? decodedBodyPart! : category

        let byLanguage = try container.decodeIfPresent([String: [String]].self, forKey: .instructionSteps) ?? [:]
        let italian = byLanguage[Exercise.italianKey] ?? []
        steps = italian.isEmpty ? (byLanguage[Exercise.englishKey] ?? []) : italian
    }

    /// Ri-codifica nello stesso schema del dataset, con le istruzioni sotto la chiave `it`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(bodyPart, forKey: .bodyPart)
        try container.encode(equipment, forKey: .equipment)
        try container.encode(target, forKey: .target)
        try container.encode(muscleGroup, forKey: .muscleGroup)
        try container.encode(secondaryMuscles, forKey: .secondaryMuscles)
        try container.encode([Exercise.italianKey: steps], forKey: .instructionSteps)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(gifPath, forKey: .gifPath)
        try container.encode(attribution, forKey: .attribution)
        // Campi nostri: si scrivono solo quando dicono qualcosa, così il file degli
        // esercizi personalizzati resta leggibile e il formato del dataset immutato.
        if !notes.isEmpty { try container.encode(notes, forKey: .notes) }
        if isCustom { try container.encode(true, forKey: .isCustom) }
        if isDeleted { try container.encode(true, forKey: .isDeleted) }
    }
}
