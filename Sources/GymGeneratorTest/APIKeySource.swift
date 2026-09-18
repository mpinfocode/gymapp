import Foundation
#if canImport(Security)
import Security
#endif

/// Da dove arriva la chiave OpenRouter.
///
/// Regola ferrea di questo eseguibile: la chiave **non si stampa mai**, nemmeno
/// in parte, non finisce in nessun file prodotto, in nessun messaggio d'errore e
/// in nessun rapporto. Di lei si dice solo da dove viene.
enum APIKeyOrigin: String {
    case environment
    case file
    case keychain

    var displayName: String {
        switch self {
        case .environment: "variabile d'ambiente"
        case .file: "file"
        case .keychain: "Portachiavi"
        }
    }
}

struct APIKey {
    let value: String
    let origin: APIKeyOrigin
}

enum APIKeyLookup {

    /// Nome della variabile d'ambiente.
    static let environmentVariable = "OPENROUTER_API_KEY"
    /// Percorso di default del file con la chiave, fuori dal repository.
    static let defaultFilePath = "~/.config/gymapp/openrouter-test.key"
    /// Voce del Portachiavi.
    static let keychainService = "gymapp-openrouter-test"
    static let keychainAccount = "openrouter"

    /// Esito della ricerca: la chiave (se trovata) e gli avvisi da mostrare.
    /// Gli avvisi non contengono mai la chiave.
    struct Outcome {
        let key: APIKey?
        let warnings: [String]
    }

    /// Cerca la chiave: variabile d'ambiente, poi file, poi Portachiavi.
    ///
    /// - Parameters:
    ///   - filePath: percorso alternativo al file (`--key-file`).
    ///   - repositoryRoot: cartella del repository; un file dentro il repository
    ///     viene rifiutato, perché la chiave non deve rischiare un commit.
    static func find(filePath: String?, repositoryRoot: URL) -> Outcome {
        var warnings: [String] = []

        if let value = sanitize(ProcessInfo.processInfo.environment[environmentVariable]) {
            return Outcome(key: APIKey(value: value, origin: .environment), warnings: warnings)
        }

        if let value = readFile(path: filePath ?? defaultFilePath, repositoryRoot: repositoryRoot, warnings: &warnings) {
            return Outcome(key: APIKey(value: value, origin: .file), warnings: warnings)
        }

        if let value = readKeychain(warnings: &warnings) {
            return Outcome(key: APIKey(value: value, origin: .keychain), warnings: warnings)
        }

        return Outcome(key: nil, warnings: warnings)
    }

    // MARK: - File

    private static func readFile(path: String, repositoryRoot: URL, warnings: inout [String]) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        // Il file non deve stare dentro il repository: una chiave lì dentro è
        // una chiave che prima o poi finisce in un commit.
        let root = repositoryRoot.standardizedFileURL.path
        if url.path.hasPrefix(root.hasSuffix("/") ? root : root + "/") {
            warnings.append("Il file della chiave si trova dentro la cartella del progetto: spostalo fuori (per esempio in \(defaultFilePath)). Ignorato.")
            return nil
        }

        // I permessi devono essere al massimo 600.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let permissions = attributes[.posixPermissions] as? NSNumber {
            let mode = permissions.uint16Value & 0o777
            if mode & 0o077 != 0 {
                warnings.append("Il file della chiave ha permessi \(String(mode, radix: 8)): troppo larghi. Esegui chmod 600 \(url.path). Ignorato.")
                return nil
            }
        }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            warnings.append("Il file della chiave esiste ma non si riesce a leggerlo.")
            return nil
        }
        return sanitize(text)
    }

    // MARK: - Portachiavi

    private static func readKeychain(warnings: inout [String]) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return sanitize(String(data: data, encoding: .utf8))
        case errSecItemNotFound:
            return nil
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            warnings.append(
                """
                Il Portachiavi ha negato l'accesso alla voce \(keychainService).
                Apri Accesso Portachiavi, cerca \(keychainService), doppio clic sulla voce,
                scheda Controllo accessi, e consenti l'accesso a questo programma;
                oppure riesegui il comando e premi "Consenti sempre" nella finestra di sistema.
                """
            )
            return nil
        default:
            warnings.append("Il Portachiavi ha risposto con l'errore \(status).")
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Pulizia

    /// Toglie spazi e a-capo; una stringa vuota vale come chiave assente.
    private static func sanitize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Spiegazione da stampare quando la chiave non c'è.
    static var missingKeyHelp: String {
        """
        Chiave OpenRouter non trovata. Si cerca, in quest'ordine:
          1. la variabile d'ambiente \(environmentVariable)
          2. il file \(defaultFilePath) (permessi 600, fuori dal repository; percorso alternativo con --key-file)
          3. il Portachiavi del Mac, voce generic password con servizio "\(keychainService)" e account "\(keychainAccount)"

        Per creare il file:
          mkdir -p ~/.config/gymapp
          printf '%s' 'la-tua-chiave' > \(defaultFilePath)
          chmod 600 \(defaultFilePath)

        Per il Portachiavi:
          security add-generic-password -U -s \(keychainService) -a \(keychainAccount) -w

        Senza chiave si può comunque provare il generatore deterministico:
          swift run GymGeneratorTest --fallback
        """
    }
}
