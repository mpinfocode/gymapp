import Foundation
import Security

// La chiave OpenRouter dell'utente.
//
// Regole non negoziabili (SPEC §0, "Scheda con l'AI"):
// - sta **solo** nel Portachiavi di questo telefono;
// - non finisce mai in `UserSettings`, nei file JSON dell'app, nei log, negli
//   screenshot o in un messaggio d'errore;
// - non si sincronizza su iCloud e non esce dal dispositivo nemmeno nei backup
//   (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`);
// - dopo il salvataggio non si rimostra mai in chiaro: la UI conosce soltanto le
//   ultime quattro cifre (``KeychainStore/maskedSuffix(of:)``).
//
// Il protocollo esiste per una ragione sola: negli screenshot e in `GymPreview`
// si inietta una versione in memoria, così gli strumenti non toccano il
// Portachiavi vero del Mac.

/// Chi custodisce un segreto (una stringa sola) per conto dell'app.
public protocol KeychainStoring: Sendable {

    /// Salva o sostituisce il segreto.
    func save(_ value: String) throws
    /// Legge il segreto; `nil` se non c'è.
    func read() throws -> String?
    /// Cancella il segreto. Non è un errore se non c'era.
    func remove() throws
}

/// Errori del Portachiavi, con messaggi italiani che **non** contengono il segreto.
public enum KeychainFailure: Error, Sendable, Hashable, CustomStringConvertible {

    /// La stringa da salvare è vuota o non codificabile.
    case invalidValue
    /// Il Portachiavi ha rifiutato l'operazione; il numero è l'`OSStatus`.
    case unexpected(status: Int32)

    public var description: String {
        switch self {
        case .invalidValue: "La chiave non è valida."
        case .unexpected(let status): "Il Portachiavi ha risposto con un errore (\(status))."
        }
    }
}

/// Implementazione vera, sul Portachiavi di sistema.
///
/// È una `generic password` con `service` fisso e un solo `account`: una chiave
/// per installazione, nessun elenco da gestire.
public struct KeychainStore: KeychainStoring {

    /// Servizio del Portachiavi per la chiave OpenRouter.
    public static let openRouterService = "it.mpinformatica.gymapp.openrouter"
    /// Unico account sotto quel servizio.
    public static let defaultAccount = "apiKey"

    private let service: String
    private let account: String

    public init(service: String = KeychainStore.openRouterService, account: String = KeychainStore.defaultAccount) {
        self.service = service
        self.account = account
    }

    /// Voce da cercare o cancellare.
    private var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Mai iCloud: la chiave resta su questo telefono.
            kSecAttrSynchronizable as String: false,
        ]
        #if os(macOS)
        // Su macOS il Portachiavi "moderno" (quello con le stesse regole di iOS)
        // va chiesto esplicitamente, altrimenti l'elemento finisce nel portachiavi
        // di login e `kSecAttrAccessible` viene ignorato.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    public func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw KeychainFailure.invalidValue
        }

        // Si cancella e si riscrive: un `SecItemUpdate` non può cambiare
        // `kSecAttrAccessible` su un elemento già esistente, e una chiave
        // sostituita deve avere la stessa protezione di una appena inserita.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainFailure.unexpected(status: status)
        }
    }

    public func read() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return nil }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainFailure.unexpected(status: status)
        }
    }

    public func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainFailure.unexpected(status: status)
        }
    }

    // MARK: - Mascheratura

    /// Ultime quattro cifre della chiave, l'unica parte che la UI può mostrare.
    ///
    /// Restituisce `nil` per le stringhe troppo corte: mostrare "ab" di una chiave
    /// da due caratteri non aiuterebbe nessuno.
    public static func maskedSuffix(of value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return nil }
        return String(trimmed.suffix(4))
    }
}

/// Portachiavi finto, in memoria: lo usano `GymSnapshots` e `GymPreview`.
///
/// Gli strumenti non devono poter leggere né scrivere il Portachiavi vero del Mac
/// di chi sviluppa, quindi l'ambiente di default di ``AppEnvironment`` monta
/// questo e solo ``AppEnvironment/makeDefault()`` monta quello di sistema.
public final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {

    private let lock = NSLock()
    private var value: String?

    /// - Parameter value: segreto già presente all'avvio (per gli screenshot).
    public init(value: String? = nil) {
        self.value = value
    }

    public func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainFailure.invalidValue }
        lock.lock()
        self.value = trimmed
        lock.unlock()
    }

    public func read() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func remove() throws {
        lock.lock()
        value = nil
        lock.unlock()
    }
}
