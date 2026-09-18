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
    /// Tollera il caso più frequente con i modelli economici: il JSON avvolto in
    /// un blocco ```` ```json ```` o preceduto da una frase di cortesia. Si
    /// prende il primo `{` e l'ultimo `}` e si prova a decodificare.
    public static func decode(fromModelOutput text: String) throws -> GeneratedProgramDraft {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw DecodingProblem.noJSONFound
        }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8) else { throw DecodingProblem.noJSONFound }
        do {
            return try JSONDecoder().decode(GeneratedProgramDraft.self, from: data)
        } catch {
            throw DecodingProblem.malformed(String(describing: error))
        }
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
