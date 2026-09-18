import Foundation

/// Contenuto di un backup completo: un unico JSON versionato.
///
/// Serve perché il sideload (reinstallazione con Apple ID gratuito ogni 7 giorni)
/// può far perdere il contenitore dell'app. Vedi SPEC §4.
public struct BackupPayload: Codable, Sendable, Hashable {

    /// Versione del formato scritta dall'app corrente.
    public static let currentVersion = 1

    /// Versione del formato del file letto/scritto.
    public let version: Int
    public let exportedAt: Date
    public let programs: [Program]
    public let sessions: [WorkoutSession]
    public let bodyEntries: [BodyEntry]
    public let settings: UserSettings
    /// Esercizi personalizzati, compresi quelli eliminati: senza di loro un backup
    /// ripristinato mostrerebbe sessioni con esercizi senza nome.
    public let customExercises: [Exercise]

    public init(
        version: Int = BackupPayload.currentVersion,
        exportedAt: Date = Date(),
        programs: [Program],
        sessions: [WorkoutSession],
        bodyEntries: [BodyEntry],
        settings: UserSettings,
        customExercises: [Exercise] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.programs = programs
        self.sessions = sessions
        self.bodyEntries = bodyEntries
        self.settings = settings
        self.customExercises = customExercises
    }

    /// Decodifica tollerante: un backup scritto da una versione futura che aggiunge
    /// collezioni resta leggibile, quelle sconosciute vengono ignorate.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? BackupPayload.currentVersion
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        programs = try c.decodeIfPresent([Program].self, forKey: .programs) ?? []
        sessions = try c.decodeIfPresent([WorkoutSession].self, forKey: .sessions) ?? []
        bodyEntries = try c.decodeIfPresent([BodyEntry].self, forKey: .bodyEntries) ?? []
        settings = try c.decodeIfPresent(UserSettings.self, forKey: .settings) ?? UserSettings()
        customExercises = try c.decodeIfPresent([Exercise].self, forKey: .customExercises) ?? []
    }

    /// Codifica in JSON (stesse regole di ``JSONCoding``, ma indentato: il file
    /// può finire in iCloud Drive o in un'email e deve restare leggibile).
    public func encoded() throws -> Data {
        let encoder = JSONCoding.makeEncoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        return try encoder.encode(self)
    }

    /// Legge un backup, rifiutando i formati troppo recenti per questa build.
    public static func decoded(from data: Data) throws -> BackupPayload {
        let payload = try JSONCoding.makeDecoder().decode(BackupPayload.self, from: data)
        guard payload.version <= currentVersion else {
            throw BackupError.unsupportedVersion(payload.version)
        }
        return payload
    }

    /// Riepilogo per la schermata di conferma import.
    public var summary: String {
        "\(programs.count) schede · \(sessions.count) allenamenti · \(bodyEntries.count) misurazioni"
    }
}

public enum BackupError: Error, Sendable, CustomStringConvertible {
    /// Il file è stato scritto da una versione più recente dell'app.
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .unsupportedVersion(let version):
            "Backup in formato versione \(version): aggiorna l'app per importarlo."
        }
    }
}
