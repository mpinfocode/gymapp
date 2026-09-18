import Foundation

/// Le collezioni persistite, una per file.
public enum StoreFile: String, Sendable, Hashable, CaseIterable {
    case programs
    case sessions
    case bodyEntries
    case settings
    case activeSession
    /// Esercizi creati dall'utente (SPEC §2, punto 5).
    case customExercises

    /// Nome del file su disco.
    public var fileName: String { "\(rawValue).json" }
}

/// Codifica/decodifica JSON condivisa da persistenza e backup.
///
/// Date in ISO 8601 (precisione al secondo) e chiavi ordinate, così i file
/// sono diffabili e il formato è stabile fra versioni dell'app.
public enum JSONCoding {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Persistenza su file JSON, un file per collezione.
///
/// La directory è iniettabile: l'app usa `Application Support/GymApp/`,
/// i check usano una cartella temporanea.
public actor JSONFileStore {

    /// Cartella in cui vivono i file.
    public let directory: URL

    private let encoder = JSONCoding.makeEncoder()
    private let decoder = JSONCoding.makeDecoder()

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/GymApp/`, creata se non esiste.
    ///
    /// Volutamente *inclusa* nel backup di sistema: sono i dati dell'utente.
    /// I media scaricati vanno invece in una cartella separata ed esclusa (vedi SPEC §2).
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("GymApp", isDirectory: true)
    }

    /// Store che scrive nella cartella di default dell'app.
    public static func makeDefault() throws -> JSONFileStore {
        JSONFileStore(directory: try defaultDirectory())
    }

    public func url(for file: StoreFile) -> URL {
        directory.appendingPathComponent(file.fileName, isDirectory: false)
    }

    public func exists(_ file: StoreFile) -> Bool {
        FileManager.default.fileExists(atPath: url(for: file).path)
    }

    /// Legge una collezione; `nil` se il file non esiste ancora (primo avvio).
    /// Un file corrotto propaga l'errore di decodifica, così l'app può avvisare
    /// invece di cancellare silenziosamente lo storico.
    public func load<T: Decodable & Sendable>(_ type: T.Type, from file: StoreFile) throws -> T? {
        let fileURL = url(for: file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        return try decoder.decode(T.self, from: data)
    }

    /// Scrive una collezione in modo atomico (scrittura su file temporaneo + rename).
    public func save<T: Encodable & Sendable>(_ value: T, to file: StoreFile) throws {
        try createDirectoryIfNeeded()
        let data = try encoder.encode(value)
        try data.write(to: url(for: file), options: [.atomic])
    }

    /// Rimuove il file di una collezione, se presente.
    public func delete(_ file: StoreFile) throws {
        let fileURL = url(for: file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Cancella tutte le collezioni (usato prima di importare un backup).
    public func deleteAll() throws {
        for file in StoreFile.allCases { try delete(file) }
    }

    private func createDirectoryIfNeeded() throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
