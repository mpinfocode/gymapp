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
    public let target: String
    /// Gruppo muscolare di appartenenza, in inglese.
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
        attribution: String = Exercise.defaultAttribution
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
    }

    /// Attribuzione da mostrare nella UI (dettaglio esercizio, Impostazioni, Crediti).
    ///
    /// Il campo `attribution` del dataset resta decodificato così com'è; questa è la
    /// forma di presentazione.
    public static let displayAttribution = "© Gym visual · https://gymvisual.com/"

    /// Attribuzione usata quando il record del dataset non ne porta una.
    public static let defaultAttribution = displayAttribution

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
    /// Gruppo muscolare tradotto in italiano.
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
    }
}
