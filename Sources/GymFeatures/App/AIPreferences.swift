import Foundation
import Observation
import GymCore

/// Tutto quello che serve alla "scheda con l'AI" fuori dalle risposte del wizard:
/// **lo stato** della chiave e il modello scelto.
///
/// Due cose vivono in posti diversi di proposito:
/// - la **chiave** sta nel Portachiavi e non esce mai da lì se non nell'istante
///   della chiamata (``apiKey()``); questa classe ne conosce soltanto la
///   presenza e le ultime quattro cifre;
/// - il **modello** è una preferenza come le altre, ma non può entrare in
///   ``UserSettings`` senza cambiare il formato dei file di GymCore: sta quindi
///   in `UserDefaults`, che è esattamente il posto per una stringa del genere.
///
/// È `@Observable` perché la sezione delle Impostazioni deve aggiornarsi da sé
/// dopo un salvataggio; ma la lettura del Portachiavi **non** avviene mai in un
/// `body`: si aggiorna ``status`` con ``refresh()`` e i `body` leggono quello.
@MainActor
@Observable
public final class AIPreferences {

    /// Stato della chiave come lo vede la UI: mai il valore, solo la presenza.
    public enum KeyStatus: Sendable, Equatable {
        /// Non è ancora stato letto il Portachiavi.
        case unknown
        /// Nessuna chiave salvata.
        case missing
        /// Chiave presente; `suffix` sono le ultime quattro cifre, se leggibili.
        case saved(suffix: String?)

        /// `true` quando una generazione con l'AI può partire.
        public var hasKey: Bool {
            if case .saved = self { return true }
            return false
        }

        /// Riga di stato mostrata in Impostazioni.
        public var displayName: String {
            switch self {
            case .unknown: "Verifica in corso"
            case .missing: "Nessuna chiave"
            case .saved(let suffix):
                if let suffix { "Chiave salvata ····\(suffix)" } else { "Chiave salvata" }
            }
        }
    }

    /// Le due sole scorciatoie che hanno senso offrire: il predefinito e
    /// "più accurato".
    ///
    /// Prima ce n'erano tre, prese dal banco di prova senza averle mai provate
    /// davvero: `openai/gpt-5-nano` ragiona per forza ed è il modello che nella
    /// prima prova reale ha restituito quattro risposte vuote su quattro, e
    /// `mistralai/mistral-small-3.2-24b-instruct` non era mai stato verificato.
    /// Restano solo id controllati su openrouter.ai il 22/09/2026.
    public static let suggestedModels = [
        AIPreferences.defaultModel,
        AIPreferences.accurateModel,
    ]

    /// Modello di default: veloce, economico e provato dal vivo
    /// (1,0 s e $0,0004 a scheda il 18/09/2026).
    public static let defaultModel = ProgramGenerationService.defaultModel

    /// Il modello "più accurato": stessa famiglia del predefinito, un gradino
    /// sopra come capacità, e comunque circa $0,002 a scheda.
    ///
    /// Restare in casa Google non è pigrizia: è l'unico fornitore su cui il
    /// formato compatto è già stato verificato dal vivo, e lo schema stretto
    /// funziona senza ripieghi.
    public static let accurateModel = "google/gemini-2.5-flash"

    /// Etichetta da mostrare accanto alla scorciatoia.
    public static func shortcutLabel(for model: String) -> String {
        switch model {
        case AIPreferences.defaultModel: "Veloce"
        case AIPreferences.accurateModel: "Più accurato"
        default: model.split(separator: "/").last.map(String.init) ?? model
        }
    }

    /// Chiave sotto cui il modello sta in `UserDefaults`.
    static let modelDefaultsKey = "it.mpinformatica.gymapp.generator.model"

    /// Il Portachiavi: quello di sistema nell'app, quello in memoria negli strumenti.
    public let keychain: any KeychainStoring

    /// Stato della chiave, aggiornato da ``refresh()``. I `body` leggono questo.
    public private(set) var status: KeyStatus = .unknown

    /// Identificativo del modello OpenRouter.
    public var model: String {
        didSet {
            let cleaned = AIPreferences.clean(model: model)
            guard cleaned != oldValue else { return }
            if cleaned != model {
                model = cleaned
                return
            }
            defaults?.set(cleaned, forKey: AIPreferences.modelDefaultsKey)
        }
    }

    private let defaults: UserDefaults?

    /// - Parameters:
    ///   - keychain: custode della chiave.
    ///   - defaults: dove salvare il modello; `nil` tiene la scelta solo in memoria
    ///     (è il caso degli screenshot e dell'anteprima).
    public init(keychain: any KeychainStoring = InMemoryKeychainStore(), defaults: UserDefaults? = nil) {
        self.keychain = keychain
        self.defaults = defaults
        let stored = defaults?.string(forKey: AIPreferences.modelDefaultsKey)
        model = AIPreferences.clean(model: stored ?? AIPreferences.defaultModel)
    }

    /// Ambiente reale: Portachiavi di sistema e `UserDefaults.standard`.
    public static func makeDefault() -> AIPreferences {
        AIPreferences(keychain: KeychainStore(), defaults: .standard)
    }

    // MARK: - Chiave

    /// Rilegge il Portachiavi e aggiorna ``status``.
    ///
    /// Da chiamare in un `.task`, mai in un `body`.
    public func refresh() {
        let value = try? keychain.read()
        guard let value, !value.isEmpty else {
            status = .missing
            return
        }
        status = .saved(suffix: KeychainStore.maskedSuffix(of: value))
    }

    /// Salva una chiave nuova. Restituisce `nil` se è andata bene, altrimenti il
    /// messaggio da mostrare (che non contiene la chiave).
    @discardableResult
    public func saveKey(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Incolla la chiave prima di salvare." }
        do {
            try keychain.save(trimmed)
            status = .saved(suffix: KeychainStore.maskedSuffix(of: trimmed))
            return nil
        } catch {
            status = .missing
            return "Non si riesce a salvare la chiave nel Portachiavi."
        }
    }

    /// Cancella la chiave. Restituisce `nil` se è andata bene.
    @discardableResult
    public func removeKey() -> String? {
        do {
            try keychain.remove()
            status = .missing
            return nil
        } catch {
            return "Non si riesce a togliere la chiave dal Portachiavi."
        }
    }

    /// La chiave, per l'istante in cui serve fare la chiamata.
    ///
    /// Va usata solo dentro il `Task` che genera: non va messa in uno `@State`,
    /// non va stampata e non va passata a niente che possa registrarla.
    public func apiKey() -> String? {
        guard let value = try? keychain.read() else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Modello

    /// Riporta il modello a quello di default.
    public func resetModel() {
        model = AIPreferences.defaultModel
    }

    /// Ripulisce l'identificativo scritto a mano: niente spazi, mai vuoto.
    static func clean(model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultModel : trimmed
    }
}
