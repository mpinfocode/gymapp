import Foundation

/// La scheda come la restituisce il modello: il formato più piccolo possibile
/// che contenga tutto quel che serve.
///
/// Niente carichi: il carico lo mette l'utente in palestra alla prima seduta
/// (SPEC §0), e un modello che lo inventasse sarebbe solo pericoloso.
public struct GeneratedProgramDraft: Codable, Sendable, Hashable {

    /// Una voce del giorno.
    public struct Item: Codable, Sendable, Hashable {
        /// `Exercise.id`, che deve essere uno dei candidati proposti.
        public var id: String
        /// Serie di lavoro.
        public var sets: Int
        /// Estremo basso del range di ripetizioni.
        public var repsMin: Int?
        /// Estremo alto del range di ripetizioni.
        public var repsMax: Int?
        /// Durata in secondi, per plank e cardio (alternativa alle ripetizioni).
        public var seconds: Int?
        /// Recupero in secondi.
        public var rest: Int
        /// Nota breve in italiano ("schiena appoggiata", "non bloccare i gomiti").
        public var note: String?

        public init(
            id: String,
            sets: Int,
            repsMin: Int? = nil,
            repsMax: Int? = nil,
            seconds: Int? = nil,
            rest: Int,
            note: String? = nil
        ) {
            self.id = id
            self.sets = sets
            self.repsMin = repsMin
            self.repsMax = repsMax
            self.seconds = seconds
            self.rest = rest
            self.note = note
        }

        /// `true` se la voce è a tempo invece che a ripetizioni.
        public var isDuration: Bool { seconds != nil && repsMin == nil }

        /// Valore che significa "il modello non l'ha detto": lo riempirà la
        /// riparazione con i numeri già calcolati dal telefono.
        ///
        /// Zero non è mai un valore lecito (le serie partono da 1, il recupero
        /// da 15 secondi), quindi non si confonde con un dato vero.
        public static let unspecified = 0

        /// La voce porta solo l'id: nessun numero, come nel formato compatto.
        public var isUnspecified: Bool {
            sets == Item.unspecified
                && rest == Item.unspecified
                && repsMin == nil
                && repsMax == nil
                && seconds == nil
        }

        /// Voce fatta del solo id, da completare con i parametri della scheda.
        public static func idOnly(_ id: String) -> Item {
            Item(id: id, sets: unspecified, rest: unspecified)
        }

        /// Obiettivo nel formato di GymCore.
        public var measure: SetMeasure {
            if let seconds, repsMin == nil { return .duration(seconds: max(1, seconds)) }
            let low = max(1, repsMin ?? 8)
            let high = max(low, repsMax ?? low)
            return .reps(min: low, max: high)
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
            sets = try c.decodeIfPresent(Int.self, forKey: .sets) ?? 3
            repsMin = try c.decodeIfPresent(Int.self, forKey: .repsMin)
            repsMax = try c.decodeIfPresent(Int.self, forKey: .repsMax)
            seconds = try c.decodeIfPresent(Int.self, forKey: .seconds)
            rest = try c.decodeIfPresent(Int.self, forKey: .rest) ?? 90
            note = try c.decodeIfPresent(String.self, forKey: .note)
        }
    }

    /// Un giorno della scheda.
    public struct Day: Codable, Sendable, Hashable {
        public var name: String
        public var items: [Item]

        public init(name: String, items: [Item]) {
            self.name = name
            self.items = items
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        }
    }

    public var name: String
    public var days: [Day]

    public init(name: String, days: [Day]) {
        self.name = name
        self.days = days
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        days = try c.decodeIfPresent([Day].self, forKey: .days) ?? []
    }

    // MARK: - Lettura della risposta del modello

    /// Errori di lettura della risposta.
    public enum DecodingProblem: Error, Sendable, CustomStringConvertible {
        case noJSONFound
        case malformed(String)

        public var description: String {
            switch self {
            case .noJSONFound: "La risposta non contiene un oggetto JSON."
            case .malformed(let detail): "JSON non interpretabile: \(detail)"
            }
        }
    }

    /// Legge la scheda dal testo restituito dal modello.
    ///
    /// Capisce due formati:
    /// - **compatto** (quello che si chiede oggi): `{"n": "...", "d": [["0025", "0031"], ...]}`,
    ///   solo id. Le voci restano senza numeri (``Item/isUnspecified``) e i
    ///   giorni senza nome: li riempie ``GeneratorValidator/repair(_:answers:parameters:candidates:)``
    ///   con i valori già calcolati dal telefono.
    /// - **esteso** (quello di prima): `{"name": ..., "days": [{"name":..., "items": [...]}]}`.
    ///   Si continua a leggerlo perché un modello può ancora produrlo, e perché
    ///   le risposte già registrate nei rapporti devono restare rileggibili.
    ///
    /// Tollera il caso più frequente con i modelli economici: il JSON avvolto in
    /// un blocco ```` ```json ```` o preceduto da una frase di cortesia. Si
    /// prende il primo `{` e l'ultimo `}` e si prova a decodificare.
    public static func decode(fromModelOutput text: String) throws -> GeneratedProgramDraft {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw DecodingProblem.noJSONFound
        }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8) else { throw DecodingProblem.noJSONFound }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let compact = decodeCompact(object) {
            return compact
        }

        do {
            return try JSONDecoder().decode(GeneratedProgramDraft.self, from: data)
        } catch {
            throw DecodingProblem.malformed(String(describing: error))
        }
    }

    /// Legge il formato compatto, `nil` se l'oggetto non è in quel formato.
    ///
    /// È scritto con `JSONSerialization` e non con `Codable` perché deve essere
    /// **generoso**: un modello economico che ha capito "elenco di id" può
    /// consegnarli come stringhe nude, come numeri, o dentro un oggettino. Tutte
    /// e tre le forme valgono lo stesso, e rifiutarne due farebbe buttare via
    /// una risposta corretta nella sostanza.
    static func decodeCompact(_ object: [String: Any]) -> GeneratedProgramDraft? {
        guard let rawDays = (object["d"] ?? object["days"]) as? [Any] else { return nil }
        // Il formato esteso ha anch'esso "days", ma fatto di oggetti con "items":
        // quello lo legge Codable.
        if rawDays.contains(where: { ($0 as? [String: Any])?["items"] != nil }) { return nil }

        let name = (object["n"] as? String) ?? (object["name"] as? String) ?? ""
        var days: [Day] = []
        for rawDay in rawDays {
            let ids = identifiers(in: rawDay)
            guard !ids.isEmpty else { continue }
            days.append(Day(name: "", items: ids.map(Item.idOnly)))
        }
        guard !days.isEmpty else { return nil }
        return GeneratedProgramDraft(name: name, days: days)
    }

    /// Gli id contenuti in un giorno del formato compatto.
    static func identifiers(in rawDay: Any) -> [String] {
        let elements: [Any]
        if let list = rawDay as? [Any] {
            elements = list
        } else if let wrapper = rawDay as? [String: Any] {
            // `{"x": [...]}`, `{"i": [...]}`, `{"items": [...]}`: si prende il
            // primo valore che sia un elenco.
            guard let list = (wrapper["x"] ?? wrapper["i"] ?? wrapper["items"] ?? wrapper["ids"]) as? [Any]
                ?? wrapper.values.first(where: { $0 is [Any] }) as? [Any]
            else { return [] }
            elements = list
        } else {
            return []
        }

        return elements.compactMap { element in
            if let text = element as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let number = element as? Int {
                // Gli id della libreria sono stringhe di quattro cifre con gli
                // zeri davanti: un modello che li scrive come numeri perderebbe
                // lo zero iniziale.
                return String(format: "%04d", number)
            }
            if let wrapper = element as? [String: Any] {
                return (wrapper["i"] ?? wrapper["id"]) as? String
            }
            return nil
        }
        .filter { !$0.isEmpty }
    }

    /// Serializzazione compatta e stabile (chiavi ordinate), utile nei rapporti.
    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// Numero totale di voci.
    public var itemCount: Int { days.reduce(0) { $0 + $1.items.count } }
}
