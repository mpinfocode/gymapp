import Foundation

/// Un esercizio della **selezione curata**: quelli che si usano davvero in una
/// palestra commerciale, etichettati con quel che serve per costruire una scheda.
///
/// La libreria ha 1.324 record, ma la gran parte sono stretching, varianti su
/// fitball, acrobazie da calisthenics e doppioni ("v. 2", "(female)", "(back pov)").
/// Un modello linguistico economico non può leggerli tutti e una scheda seria non
/// li userebbe comunque: questa selezione è il vocabolario del generatore.
///
/// La riga porta **solo** le etichette che il dataset non sa dare (schema motorio,
/// livello, attrezzatura, zone sollecitate, quanto è un classico). Nome, gruppo
/// muscolare e attrezzo si leggono a runtime dalla libreria, così restano
/// allineati a ``ExerciseCorrections`` senza copie da tenere aggiornate a mano.
public struct CuratedExercise: Sendable, Hashable, Identifiable {

    /// `Exercise.id` del dataset (stringa con zeri iniziali, es. `"0025"`).
    public let id: String
    /// Schema motorio: è la chiave con cui si riempiono i giorni della scheda.
    public let pattern: MovementPattern
    /// Multiarticolare o isolamento.
    public let kind: ExerciseKind
    /// Esperienza minima perché abbia senso metterlo in scheda.
    public let level: TrainingLevel
    /// Attrezzatura minima necessaria.
    public let equipment: EquipmentClass
    /// Quanto è un "classico da scheda": 1 = pilastro, 2 = valida alternativa,
    /// 3 = accessorio o variante da usare solo per variare.
    public let priority: Int
    /// Zone a rischio che l'esercizio sollecita in modo marcato.
    public let stress: Set<StressZone>

    /// Inizializzatore posizionale: la tabella qui sotto è lunga, e con le
    /// etichette diventerebbe illeggibile. L'ordine è
    /// id, pattern, tipo, livello, attrezzatura, priorità, zone sollecitate.
    public init(
        _ id: String,
        _ pattern: MovementPattern,
        _ kind: ExerciseKind,
        _ level: TrainingLevel,
        _ equipment: EquipmentClass,
        _ priority: Int,
        _ stress: Set<StressZone> = []
    ) {
        self.id = id
        self.pattern = pattern
        self.kind = kind
        self.level = level
        self.equipment = equipment
        self.priority = max(1, min(3, priority))
        self.stress = stress
    }

    /// `true` se l'esercizio è adatto a chi ha quell'esperienza.
    public func suits(level userLevel: TrainingLevel) -> Bool { level <= userLevel }

    /// `true` se l'esercizio è fattibile con quell'attrezzatura.
    public func suits(equipment available: EquipmentClass) -> Bool { equipment.rank <= available.rank }

    /// `true` se l'esercizio non tocca nessuna delle zone da proteggere.
    public func respects(protectedZones: Set<StressZone>) -> Bool { stress.isDisjoint(with: protectedZones) }
}

/// Fonte di esercizi per il generatore: la libreria del dataset o l'indice che
/// comprende anche i personalizzati.
public protocol ExerciseSource: Sendable {
    func exercise(id: String) -> Exercise?
}

extension ExerciseRepository: ExerciseSource {}
extension ExerciseLibraryIndex: ExerciseSource {}

/// Esercizio della selezione **risolto** sulla libreria: etichette curate più
/// nome, gruppo muscolare e attrezzo veri.
public struct ResolvedExercise: Sendable, Hashable, Identifiable {

    public let curated: CuratedExercise
    public let exercise: Exercise

    public init(curated: CuratedExercise, exercise: Exercise) {
        self.curated = curated
        self.exercise = exercise
    }

    public var id: String { curated.id }
    public var pattern: MovementPattern { curated.pattern }
    public var kind: ExerciseKind { curated.kind }
    public var level: TrainingLevel { curated.level }
    public var equipmentClass: EquipmentClass { curated.equipment }
    public var priority: Int { curated.priority }
    public var stress: Set<StressZone> { curated.stress }

    /// Gruppo muscolare "da palestra", calcolato dal `target` già corretto.
    public var group: MuscleGroup { exercise.muscleGroupKind }
    /// Titolo senza il prefisso dell'attrezzo (SPEC §0).
    public var shortName: String { exercise.shortDisplayName }
    /// Attrezzo in italiano.
    public var localizedEquipment: String { exercise.localizedEquipment }
}

/// La selezione curata: circa 250 esercizi scelti a mano fra i 1.324 del dataset.
///
/// Criteri di ammissione, applicati con la testa del preparatore:
/// 1. **Si usa davvero** in una palestra commerciale o a casa. Fuori stretching,
///    mobilità, planche, front lever, muscle-up, lanci di palla medica, esercizi
///    da atletica.
/// 2. **Niente doppioni**: una sola variante per movimento e attrezzo, mai le
///    varianti ridondanti del dataset (``Exercise/isRedundantVariant``).
/// 3. **Copertura completa**: tutti i gruppi di ``MuscleGroup`` (escluso `other`)
///    e tutte e tre le classi di attrezzatura, con abbastanza esercizi da
///    costruire una scheda intera anche con soli manubri e panca o con il solo
///    corpo libero più elastici.
/// 4. **Ogni id verificato** sul JSON (nome, attrezzo, muscolo) e ricontrollato
///    a ogni build da `GymChecks` (`runGeneratorPoolChecks`).
public enum CuratedExercisePool {

    /// La tabella. Una riga per esercizio, il nome del dataset nel commento.
    ///
    /// Ordinata per schema motorio e, dentro ciascuno, per attrezzatura crescente
    /// e priorità: si legge come un catalogo.
    public static let all: [CuratedExercise] = [
        // MARK: Estensioni lombari
        .init("0489", .backExtension, .isolation, .beginner, .bodyweightBands, 1, [.lowerBack]),  // hyperextension
        .init("0573", .backExtension, .isolation, .beginner, .gym, 1, [.lowerBack]),  // lever back extension
        .init("0593", .backExtension, .isolation, .beginner, .gym, 3, [.lowerBack]),  // lever reverse hyperextension

        // MARK: Isolamento dorso
        .init("0238", .backIsolation, .isolation, .beginner, .gym, 1, []),  // cable straight arm pulldown
        .init("0237", .backIsolation, .isolation, .beginner, .gym, 2, []),  // cable straight arm pulldown (with rope)
        .init("2285", .backIsolation, .isolation, .beginner, .gym, 3, []),  // lever pullover

        // MARK: Bicipiti
        .init("3123", .bicepsCurl, .isolation, .beginner, .bodyweightBands, 1, []),  // resistance band seated biceps curl
        .init("0968", .bicepsCurl, .isolation, .beginner, .bodyweightBands, 2, []),  // band alternating biceps curl
        .init("0976", .bicepsCurl, .isolation, .beginner, .bodyweightBands, 3, []),  // band concentration curl
        .init("0294", .bicepsCurl, .isolation, .beginner, .dumbbellBench, 1, []),  // dumbbell biceps curl
        .init("0313", .bicepsCurl, .isolation, .beginner, .dumbbellBench, 1, []),  // dumbbell hammer curl
        .init("0297", .bicepsCurl, .isolation, .beginner, .dumbbellBench, 2, []),  // dumbbell concentration curl
        .init("0318", .bicepsCurl, .isolation, .beginner, .dumbbellBench, 2, []),  // dumbbell incline curl
        .init("0372", .bicepsCurl, .isolation, .beginner, .dumbbellBench, 2, []),  // dumbbell preacher curl
        .init("0429", .bicepsCurl, .isolation, .beginner, .dumbbellBench, 3, []),  // dumbbell standing reverse curl
        .init("0439", .bicepsCurl, .isolation, .intermediate, .dumbbellBench, 3, []),  // dumbbell zottman curl
        .init("0031", .bicepsCurl, .isolation, .beginner, .gym, 1, [.wristsElbows]),  // barbell curl
        .init("0447", .bicepsCurl, .isolation, .beginner, .gym, 1, []),  // ez barbell curl
        .init("0575", .bicepsCurl, .isolation, .beginner, .gym, 1, []),  // lever bicep curl
        .init("0868", .bicepsCurl, .isolation, .beginner, .gym, 1, []),  // cable curl
        .init("0070", .bicepsCurl, .isolation, .beginner, .gym, 2, [.wristsElbows]),  // barbell preacher curl
        .init("0165", .bicepsCurl, .isolation, .beginner, .gym, 2, []),  // cable hammer curl (with rope)
        .init("0592", .bicepsCurl, .isolation, .beginner, .gym, 2, []),  // lever preacher curl
        .init("0195", .bicepsCurl, .isolation, .beginner, .gym, 3, []),  // cable preacher curl

        // MARK: Polpacci
        .init("1373", .calf, .isolation, .beginner, .bodyweightBands, 1, []),  // bodyweight standing calf raise
        .init("0999", .calf, .isolation, .beginner, .bodyweightBands, 2, []),  // band single leg calf raise
        .init("1387", .calf, .isolation, .beginner, .bodyweightBands, 2, []),  // one leg floor calf raise
        .init("1490", .calf, .isolation, .beginner, .bodyweightBands, 2, []),  // standing calf raise (on a staircase)
        .init("0284", .calf, .isolation, .beginner, .bodyweightBands, 3, []),  // donkey calf raise
        .init("0417", .calf, .isolation, .beginner, .dumbbellBench, 1, []),  // dumbbell standing calf raise
        .init("0409", .calf, .isolation, .beginner, .dumbbellBench, 2, []),  // dumbbell single leg calf raise
        .init("1379", .calf, .isolation, .beginner, .dumbbellBench, 2, []),  // dumbbell seated calf raise
        .init("0594", .calf, .isolation, .beginner, .gym, 1, []),  // lever seated calf raise
        .init("0605", .calf, .isolation, .beginner, .gym, 1, []),  // lever standing calf raise
        .init("0738", .calf, .isolation, .beginner, .gym, 2, []),  // sled 45° calf press
        .init("1372", .calf, .isolation, .beginner, .gym, 2, []),  // barbell standing calf raise
        .init("2289", .calf, .isolation, .beginner, .gym, 2, []),  // lever calf press
        .init("0088", .calf, .isolation, .beginner, .gym, 3, []),  // barbell seated calf raise
        .init("0773", .calf, .isolation, .beginner, .gym, 3, []),  // smith standing leg calf raise

        // MARK: Cardio
        .init("0630", .cardio, .isolation, .beginner, .bodyweightBands, 1, []),  // mountain climber
        .init("0685", .cardio, .isolation, .beginner, .bodyweightBands, 1, []),  // run
        .init("1160", .cardio, .isolation, .intermediate, .bodyweightBands, 1, [.knees]),  // burpee
        .init("2612", .cardio, .isolation, .beginner, .bodyweightBands, 1, []),  // jump rope
        .init("3636", .cardio, .isolation, .beginner, .bodyweightBands, 2, []),  // high knee against wall
        .init("3361", .cardio, .isolation, .intermediate, .bodyweightBands, 3, [.knees]),  // skater hops
        .init("2141", .cardio, .isolation, .beginner, .gym, 1, []),  // walk elliptical cross trainer
        .init("2331", .cardio, .isolation, .beginner, .gym, 1, []),  // cycle cross trainer
        .init("3666", .cardio, .isolation, .beginner, .gym, 1, []),  // walking on incline treadmill
        .init("0798", .cardio, .isolation, .beginner, .gym, 2, []),  // stationary bike walk
        .init("2311", .cardio, .isolation, .beginner, .gym, 2, []),  // walking on stepmill

        // MARK: Isolamento petto
        .init("0308", .chestIsolation, .isolation, .intermediate, .dumbbellBench, 2, [.shoulders]),  // dumbbell fly
        .init("0319", .chestIsolation, .isolation, .intermediate, .dumbbellBench, 2, [.shoulders]),  // dumbbell incline fly
        .init("0375", .chestIsolation, .isolation, .intermediate, .dumbbellBench, 3, [.shoulders]),  // dumbbell pullover
        .init("0596", .chestIsolation, .isolation, .beginner, .gym, 1, []),  // lever seated fly
        .init("0155", .chestIsolation, .isolation, .beginner, .gym, 2, []),  // cable cross-over variation
        .init("0179", .chestIsolation, .isolation, .beginner, .gym, 2, []),  // cable low fly
        .init("0188", .chestIsolation, .isolation, .beginner, .gym, 2, []),  // cable middle fly
        .init("1270", .chestIsolation, .isolation, .beginner, .gym, 3, []),  // cable upper chest crossovers

        // MARK: Core anti-estensione
        .init("0276", .coreAntiExtension, .isolation, .beginner, .bodyweightBands, 1, []),  // dead bug
        .init("2135", .coreAntiExtension, .isolation, .beginner, .bodyweightBands, 1, []),  // weighted front plank
        .init("0805", .coreAntiExtension, .isolation, .advanced, .bodyweightBands, 3, [.lowerBack]),  // suspended abdominal fallout
        .init("0857", .coreAntiExtension, .isolation, .advanced, .dumbbellBench, 3, [.lowerBack]),  // wheel rollerout
        .init("0084", .coreAntiExtension, .isolation, .advanced, .gym, 3, [.lowerBack]),  // barbell rollerout

        // MARK: Core in flessione
        .init("0274", .coreFlexion, .isolation, .beginner, .bodyweightBands, 1, []),  // crunch floor
        .init("0472", .coreFlexion, .isolation, .intermediate, .bodyweightBands, 1, []),  // hanging leg raise
        .init("0872", .coreFlexion, .isolation, .beginner, .bodyweightBands, 1, []),  // reverse crunch
        .init("0001", .coreFlexion, .isolation, .beginner, .bodyweightBands, 2, []),  // 3/4 sit-up
        .init("0003", .coreFlexion, .isolation, .beginner, .bodyweightBands, 2, []),  // air bike
        .init("0277", .coreFlexion, .isolation, .intermediate, .bodyweightBands, 2, []),  // decline crunch
        .init("0475", .coreFlexion, .isolation, .advanced, .bodyweightBands, 2, []),  // hanging straight leg raise
        .init("0620", .coreFlexion, .isolation, .beginner, .bodyweightBands, 2, []),  // lying leg raise flat bench
        .init("0260", .coreFlexion, .isolation, .intermediate, .bodyweightBands, 3, []),  // cocoons
        .init("0282", .coreFlexion, .isolation, .intermediate, .bodyweightBands, 3, []),  // decline sit-up
        .init("0570", .coreFlexion, .isolation, .beginner, .bodyweightBands, 3, []),  // leg pull in flat bench
        .init("0175", .coreFlexion, .isolation, .beginner, .gym, 1, []),  // cable kneeling crunch
        .init("1452", .coreFlexion, .isolation, .beginner, .gym, 1, []),  // lever seated crunch
        .init("0873", .coreFlexion, .isolation, .beginner, .gym, 2, []),  // cable reverse crunch
        .init("0212", .coreFlexion, .isolation, .beginner, .gym, 3, []),  // cable seated crunch

        // MARK: Core in rotazione e flessione laterale
        .init("0979", .coreRotation, .isolation, .beginner, .bodyweightBands, 1, []),  // band horizontal pallof press
        .init("3544", .coreRotation, .isolation, .beginner, .bodyweightBands, 1, []),  // bodyweight incline side plank
        .init("0262", .coreRotation, .isolation, .beginner, .bodyweightBands, 2, []),  // cross body crunch
        .init("0635", .coreRotation, .isolation, .beginner, .bodyweightBands, 2, []),  // oblique crunches floor
        .init("0687", .coreRotation, .isolation, .beginner, .bodyweightBands, 2, [.lowerBack]),  // russian twist
        .init("1015", .coreRotation, .isolation, .beginner, .bodyweightBands, 3, []),  // band vertical pallof press
        .init("0407", .coreRotation, .isolation, .beginner, .dumbbellBench, 2, []),  // dumbbell side bend
        .init("0243", .coreRotation, .isolation, .beginner, .gym, 2, []),  // cable twist
        .init("0222", .coreRotation, .isolation, .beginner, .gym, 3, []),  // cable side bend

        // MARK: Avambracci
        .init("1016", .forearm, .isolation, .beginner, .bodyweightBands, 1, [.wristsElbows]),  // band wrist curl
        .init("0994", .forearm, .isolation, .beginner, .bodyweightBands, 3, [.wristsElbows]),  // band reverse wrist curl
        .init("0369", .forearm, .isolation, .beginner, .dumbbellBench, 1, [.wristsElbows]),  // dumbbell over bench wrist curl
        .init("0385", .forearm, .isolation, .beginner, .dumbbellBench, 2, [.wristsElbows]),  // dumbbell reverse wrist curl
        .init("0126", .forearm, .isolation, .beginner, .gym, 1, [.wristsElbows]),  // barbell wrist curl
        .init("0082", .forearm, .isolation, .beginner, .gym, 3, [.wristsElbows]),  // barbell reverse wrist curl
        .init("0210", .forearm, .isolation, .beginner, .gym, 3, [.wristsElbows]),  // cable reverse wrist curl
        .init("0247", .forearm, .isolation, .beginner, .gym, 3, [.wristsElbows]),  // cable wrist curl

        // MARK: Anca dominante
        .init("1009", .hinge, .compound, .beginner, .bodyweightBands, 1, [.lowerBack]),  // band stiff leg deadlift
        .init("1408", .hinge, .isolation, .beginner, .bodyweightBands, 1, []),  // band hip lift
        .init("3013", .hinge, .isolation, .beginner, .bodyweightBands, 1, []),  // low glute bridge on floor
        .init("0130", .hinge, .isolation, .beginner, .bodyweightBands, 2, []),  // bench hip extension
        .init("0991", .hinge, .compound, .beginner, .bodyweightBands, 2, [.lowerBack]),  // band pull through
        .init("1422", .hinge, .isolation, .beginner, .bodyweightBands, 2, []),  // pelvic tilt into bridge
        .init("3645", .hinge, .isolation, .beginner, .bodyweightBands, 2, []),  // single leg bridge with outstretched leg
        .init("0300", .hinge, .compound, .beginner, .dumbbellBench, 1, [.lowerBack]),  // dumbbell deadlift
        .init("1459", .hinge, .compound, .beginner, .dumbbellBench, 1, [.lowerBack]),  // dumbbell romanian deadlift
        .init("0432", .hinge, .compound, .intermediate, .dumbbellBench, 2, [.lowerBack]),  // dumbbell stiff leg deadlift
        .init("0549", .hinge, .compound, .intermediate, .dumbbellBench, 2, [.lowerBack]),  // kettlebell swing
        .init("1757", .hinge, .compound, .intermediate, .dumbbellBench, 3, [.lowerBack]),  // dumbbell single leg deadlift
        .init("0032", .hinge, .compound, .advanced, .gym, 1, [.lowerBack]),  // barbell deadlift
        .init("0085", .hinge, .compound, .intermediate, .gym, 1, [.lowerBack]),  // barbell romanian deadlift
        .init("0116", .hinge, .compound, .intermediate, .gym, 2, [.lowerBack]),  // barbell straight leg deadlift
        .init("0117", .hinge, .compound, .advanced, .gym, 2, [.lowerBack]),  // barbell sumo deadlift
        .init("0196", .hinge, .compound, .beginner, .gym, 2, [.lowerBack]),  // cable pull through (with rope)
        .init("1409", .hinge, .compound, .beginner, .gym, 2, []),  // barbell glute bridge
        .init("0044", .hinge, .compound, .advanced, .gym, 3, [.lowerBack]),  // barbell good morning
        .init("0811", .hinge, .compound, .intermediate, .gym, 3, [.lowerBack]),  // trap bar deadlift

        // MARK: Tirata orizzontale
        .init("0499", .horizontalPull, .compound, .intermediate, .bodyweightBands, 1, []),  // inverted row
        .init("3144", .horizontalPull, .compound, .beginner, .bodyweightBands, 1, []),  // resistance band seated straight back row
        .init("0988", .horizontalPull, .compound, .beginner, .bodyweightBands, 2, []),  // band one arm standing low row
        .init("2300", .horizontalPull, .compound, .beginner, .bodyweightBands, 2, []),  // inverted row bent knees
        .init("0292", .horizontalPull, .compound, .beginner, .dumbbellBench, 1, []),  // dumbbell one arm bent-over row
        .init("0293", .horizontalPull, .compound, .beginner, .dumbbellBench, 1, [.lowerBack]),  // dumbbell bent over row
        .init("0027", .horizontalPull, .compound, .intermediate, .gym, 1, [.lowerBack]),  // barbell bent over row
        .init("0861", .horizontalPull, .compound, .beginner, .gym, 1, []),  // cable seated row
        .init("1350", .horizontalPull, .compound, .beginner, .gym, 1, []),  // lever seated row
        .init("0180", .horizontalPull, .compound, .beginner, .gym, 2, []),  // cable low seated row
        .init("0581", .horizontalPull, .compound, .beginner, .gym, 2, []),  // lever high row
        .init("0606", .horizontalPull, .compound, .intermediate, .gym, 2, [.lowerBack]),  // lever t bar row
        .init("0118", .horizontalPull, .compound, .intermediate, .gym, 3, [.lowerBack]),  // barbell reverse grip bent over row
        .init("0218", .horizontalPull, .compound, .beginner, .gym, 3, []),  // cable seated wide-grip row
        .init("1359", .horizontalPull, .compound, .intermediate, .gym, 3, [.lowerBack]),  // smith bent over row
        .init("3017", .horizontalPull, .compound, .advanced, .gym, 3, [.lowerBack]),  // barbell pendlay row

        // MARK: Spinta orizzontale
        .init("0251", .horizontalPush, .compound, .intermediate, .bodyweightBands, 1, [.shoulders]),  // chest dip
        .init("0259", .horizontalPush, .compound, .beginner, .bodyweightBands, 1, [.wristsElbows]),  // close-grip push-up
        .init("0493", .horizontalPush, .compound, .beginner, .bodyweightBands, 1, []),  // incline push-up
        .init("0662", .horizontalPush, .compound, .beginner, .bodyweightBands, 1, []),  // push-up
        .init("3124", .horizontalPush, .compound, .beginner, .bodyweightBands, 1, []),  // resistance band seated chest press
        .init("0279", .horizontalPush, .compound, .intermediate, .bodyweightBands, 2, []),  // decline push-up
        .init("0283", .horizontalPush, .compound, .intermediate, .bodyweightBands, 2, [.wristsElbows]),  // diamond push-up
        .init("1254", .horizontalPush, .compound, .beginner, .bodyweightBands, 2, []),  // band bench press
        .init("1311", .horizontalPush, .compound, .beginner, .bodyweightBands, 3, [.shoulders]),  // wide hand push up
        .init("0289", .horizontalPush, .compound, .beginner, .dumbbellBench, 1, []),  // dumbbell bench press
        .init("0314", .horizontalPush, .compound, .beginner, .dumbbellBench, 1, []),  // dumbbell incline bench press
        .init("0296", .horizontalPush, .compound, .beginner, .dumbbellBench, 2, []),  // dumbbell close-grip press
        .init("0301", .horizontalPush, .compound, .intermediate, .dumbbellBench, 3, []),  // dumbbell decline bench press
        .init("0025", .horizontalPush, .compound, .intermediate, .gym, 1, [.shoulders]),  // barbell bench press
        .init("0030", .horizontalPush, .compound, .intermediate, .gym, 1, [.wristsElbows]),  // barbell close-grip bench press
        .init("0047", .horizontalPush, .compound, .intermediate, .gym, 1, [.shoulders]),  // barbell incline bench press
        .init("0577", .horizontalPush, .compound, .beginner, .gym, 1, []),  // lever chest press
        .init("1299", .horizontalPush, .compound, .beginner, .gym, 1, []),  // lever incline chest press
        .init("0033", .horizontalPush, .compound, .intermediate, .gym, 2, [.shoulders]),  // barbell decline bench press
        .init("0748", .horizontalPush, .compound, .beginner, .gym, 2, []),  // smith bench press
        .init("0757", .horizontalPush, .compound, .beginner, .gym, 2, []),  // smith incline bench press
        .init("2144", .horizontalPush, .compound, .beginner, .gym, 2, []),  // cable seated chest press
        .init("0751", .horizontalPush, .compound, .beginner, .gym, 3, [.wristsElbows]),  // smith close-grip bench press

        // MARK: Alzate per le spalle
        .init("0977", .lateralRaise, .isolation, .beginner, .bodyweightBands, 2, []),  // band front lateral raise
        .init("0978", .lateralRaise, .isolation, .beginner, .bodyweightBands, 3, []),  // band front raise
        .init("0334", .lateralRaise, .isolation, .beginner, .dumbbellBench, 1, []),  // dumbbell lateral raise
        .init("0310", .lateralRaise, .isolation, .beginner, .dumbbellBench, 2, []),  // dumbbell front raise
        .init("0396", .lateralRaise, .isolation, .beginner, .dumbbellBench, 2, []),  // dumbbell seated lateral raise
        .init("0178", .lateralRaise, .isolation, .beginner, .gym, 1, []),  // cable lateral raise
        .init("0192", .lateralRaise, .isolation, .beginner, .gym, 2, []),  // cable one arm lateral raise
        .init("0584", .lateralRaise, .isolation, .beginner, .gym, 2, []),  // lever lateral raise
        .init("0162", .lateralRaise, .isolation, .beginner, .gym, 3, []),  // cable front raise
        .init("0246", .lateralRaise, .isolation, .intermediate, .gym, 3, [.shoulders]),  // cable upright row

        // MARK: Isolamento gambe
        .init("0496", .legIsolation, .compound, .intermediate, .bodyweightBands, 2, []),  // inverse leg curl (bench support)
        .init("3006", .legIsolation, .isolation, .beginner, .bodyweightBands, 2, []),  // resistance band seated hip abduction
        .init("3193", .legIsolation, .compound, .advanced, .bodyweightBands, 2, []),  // glute-ham raise
        .init("0710", .legIsolation, .isolation, .beginner, .bodyweightBands, 3, []),  // side hip abduction
        .init("0795", .legIsolation, .isolation, .beginner, .bodyweightBands, 3, []),  // standing single leg curl
        .init("1489", .legIsolation, .isolation, .advanced, .bodyweightBands, 3, [.knees]),  // sissy squat
        .init("3007", .legIsolation, .isolation, .beginner, .bodyweightBands, 3, []),  // resistance band leg extension
        .init("0339", .legIsolation, .isolation, .beginner, .dumbbellBench, 3, []),  // dumbbell lying femoral
        .init("0585", .legIsolation, .isolation, .beginner, .gym, 1, [.knees]),  // lever leg extension
        .init("0586", .legIsolation, .isolation, .beginner, .gym, 1, []),  // lever lying leg curl
        .init("0599", .legIsolation, .isolation, .beginner, .gym, 1, []),  // lever seated leg curl
        .init("0582", .legIsolation, .isolation, .beginner, .gym, 2, []),  // lever kneeling leg curl
        .init("0597", .legIsolation, .isolation, .beginner, .gym, 2, []),  // lever seated hip abduction
        .init("0228", .legIsolation, .isolation, .beginner, .gym, 3, []),  // cable standing hip extension

        // MARK: Affondi e monolaterali
        .init("1460", .lunge, .compound, .beginner, .bodyweightBands, 1, []),  // walking lunge
        .init("2368", .lunge, .compound, .beginner, .bodyweightBands, 1, []),  // split squats
        .init("1001", .lunge, .compound, .intermediate, .bodyweightBands, 2, []),  // band single leg split squat
        .init("0336", .lunge, .compound, .beginner, .dumbbellBench, 1, []),  // dumbbell lunge
        .init("0410", .lunge, .compound, .intermediate, .dumbbellBench, 1, []),  // dumbbell single leg split squat
        .init("0381", .lunge, .compound, .beginner, .dumbbellBench, 2, []),  // dumbbell rear lunge
        .init("0431", .lunge, .compound, .beginner, .dumbbellBench, 2, []),  // dumbbell step-up
        .init("0054", .lunge, .compound, .intermediate, .gym, 2, [.knees]),  // barbell lunge
        .init("0078", .lunge, .compound, .intermediate, .gym, 3, [.knees]),  // barbell rear lunge
        .init("0114", .lunge, .compound, .intermediate, .gym, 3, [.knees]),  // barbell step-up
        .init("0768", .lunge, .compound, .intermediate, .gym, 3, [.knees]),  // smith single leg split squat

        // MARK: Deltoide posteriore
        .init("0993", .rearDelt, .isolation, .beginner, .bodyweightBands, 1, []),  // band reverse fly
        .init("1017", .rearDelt, .isolation, .beginner, .bodyweightBands, 3, []),  // band y-raise
        .init("0383", .rearDelt, .isolation, .beginner, .dumbbellBench, 1, []),  // dumbbell reverse fly
        .init("2292", .rearDelt, .isolation, .beginner, .dumbbellBench, 2, []),  // dumbbell rear delt raise
        .init("0233", .rearDelt, .isolation, .beginner, .gym, 1, []),  // cable standing rear delt row (with rope)
        .init("0602", .rearDelt, .isolation, .beginner, .gym, 1, []),  // lever seated reverse fly
        .init("0154", .rearDelt, .isolation, .beginner, .gym, 2, []),  // cable cross-over revers fly

        // MARK: Scrollate
        .init("0406", .shrug, .isolation, .beginner, .dumbbellBench, 1, []),  // dumbbell shrug
        .init("1018", .shrug, .isolation, .beginner, .bodyweightBands, 1, []),  // band shrug
        .init("0095", .shrug, .isolation, .beginner, .gym, 1, []),  // barbell shrug
        .init("0220", .shrug, .isolation, .beginner, .gym, 3, []),  // cable shrug

        // MARK: Squat e ginocchio dominante
        .init("1004", .squat, .compound, .beginner, .bodyweightBands, 1, []),  // band squat
        .init("0624", .squat, .isolation, .beginner, .bodyweightBands, 2, []),  // march sit (wall)
        .init("0514", .squat, .compound, .advanced, .bodyweightBands, 3, [.knees]),  // jump squat
        .init("1760", .squat, .compound, .beginner, .dumbbellBench, 1, []),  // dumbbell goblet squat
        .init("0413", .squat, .compound, .beginner, .dumbbellBench, 2, []),  // dumbbell squat
        .init("0534", .squat, .compound, .beginner, .dumbbellBench, 2, []),  // kettlebell goblet squat
        .init("0043", .squat, .compound, .intermediate, .gym, 1, [.knees, .lowerBack]),  // barbell full squat
        .init("0739", .squat, .compound, .beginner, .gym, 1, []),  // sled 45° leg press
        .init("0042", .squat, .compound, .advanced, .gym, 2, [.knees, .lowerBack]),  // barbell front squat
        .init("0743", .squat, .compound, .beginner, .gym, 2, [.knees]),  // sled hack squat
        .init("0770", .squat, .compound, .beginner, .gym, 2, [.knees]),  // smith squat
        .init("1436", .squat, .compound, .intermediate, .gym, 2, [.knees, .lowerBack]),  // barbell high bar squat
        .init("0750", .squat, .compound, .beginner, .gym, 3, [.knees]),  // smith chair squat

        // MARK: Tricipiti
        .init("0814", .tricepsExtension, .compound, .intermediate, .bodyweightBands, 1, [.shoulders]),  // triceps dip
        .init("0998", .tricepsExtension, .isolation, .beginner, .bodyweightBands, 1, []),  // band side triceps extension
        .init("0129", .tricepsExtension, .compound, .beginner, .bodyweightBands, 2, [.shoulders]),  // bench dip (knees bent)
        .init("2188", .tricepsExtension, .isolation, .beginner, .dumbbellBench, 1, [.wristsElbows]),  // dumbbell seated triceps extension
        .init("0333", .tricepsExtension, .isolation, .beginner, .dumbbellBench, 2, []),  // dumbbell kickback
        .init("0351", .tricepsExtension, .isolation, .beginner, .dumbbellBench, 2, [.wristsElbows]),  // dumbbell lying triceps extension
        .init("0430", .tricepsExtension, .isolation, .beginner, .dumbbellBench, 2, [.wristsElbows]),  // dumbbell standing triceps extension
        .init("0194", .tricepsExtension, .isolation, .beginner, .gym, 1, []),  // cable overhead triceps extension (rope attachment)
        .init("0200", .tricepsExtension, .isolation, .beginner, .gym, 1, []),  // cable pushdown (with rope attachment)
        .init("0201", .tricepsExtension, .isolation, .beginner, .gym, 1, []),  // cable pushdown
        .init("0607", .tricepsExtension, .isolation, .beginner, .gym, 1, []),  // lever triceps extension
        .init("0060", .tricepsExtension, .isolation, .intermediate, .gym, 2, [.wristsElbows]),  // barbell lying triceps extension skull crusher
        .init("0241", .tricepsExtension, .isolation, .beginner, .gym, 2, []),  // cable triceps pushdown (v-bar)
        .init("0453", .tricepsExtension, .isolation, .intermediate, .gym, 2, [.wristsElbows]),  // ez barbell seated triceps extension
        .init("1451", .tricepsExtension, .isolation, .beginner, .gym, 2, [.shoulders]),  // lever seated dip
        .init("0092", .tricepsExtension, .isolation, .intermediate, .gym, 3, [.wristsElbows]),  // barbell seated overhead triceps extension
        .init("0207", .tricepsExtension, .isolation, .beginner, .gym, 3, []),  // cable reverse-grip pushdown
        .init("0860", .tricepsExtension, .isolation, .beginner, .gym, 3, []),  // cable kickback
        .init("1749", .tricepsExtension, .isolation, .intermediate, .gym, 3, [.wristsElbows]),  // ez bar standing french press

        // MARK: Tirata verticale
        .init("0652", .verticalPull, .compound, .advanced, .bodyweightBands, 1, []),  // pull-up
        .init("1013", .verticalPull, .compound, .beginner, .bodyweightBands, 1, []),  // band underhand pulldown
        .init("1326", .verticalPull, .compound, .advanced, .bodyweightBands, 1, []),  // chin-up
        .init("0140", .verticalPull, .compound, .advanced, .bodyweightBands, 2, []),  // biceps pull-up
        .init("0651", .verticalPull, .compound, .advanced, .bodyweightBands, 2, []),  // pull up (neutral grip)
        .init("0974", .verticalPull, .compound, .beginner, .bodyweightBands, 2, []),  // band close-grip pulldown
        .init("0017", .verticalPull, .compound, .beginner, .gym, 1, []),  // assisted pull-up
        .init("0198", .verticalPull, .compound, .beginner, .gym, 1, []),  // cable pulldown
        .init("0579", .verticalPull, .compound, .beginner, .gym, 1, []),  // lever front pulldown
        .init("0245", .verticalPull, .compound, .beginner, .gym, 2, []),  // cable underhand pulldown

        // MARK: Spinta verticale
        .init("0997", .verticalPush, .compound, .beginner, .bodyweightBands, 1, []),  // band shoulder press
        .init("3122", .verticalPush, .compound, .beginner, .bodyweightBands, 2, []),  // resistance band seated shoulder press
        .init("0405", .verticalPush, .compound, .beginner, .dumbbellBench, 1, []),  // dumbbell seated shoulder press
        .init("0426", .verticalPush, .compound, .intermediate, .dumbbellBench, 1, []),  // dumbbell standing overhead press
        .init("2137", .verticalPush, .compound, .intermediate, .dumbbellBench, 2, []),  // dumbbell arnold press
        .init("0553", .verticalPush, .compound, .intermediate, .dumbbellBench, 3, []),  // kettlebell two arm military press
        .init("0091", .verticalPush, .compound, .intermediate, .gym, 1, []),  // barbell seated overhead press
        .init("0603", .verticalPush, .compound, .beginner, .gym, 1, []),  // lever shoulder press
        .init("1456", .verticalPush, .compound, .intermediate, .gym, 2, []),  // barbell standing close grip military press
        .init("0086", .verticalPush, .compound, .advanced, .gym, 3, [.shoulders]),  // barbell seated behind head military press
        .init("0219", .verticalPush, .compound, .beginner, .gym, 3, []),  // cable shoulder press
        .init("0766", .verticalPush, .compound, .beginner, .gym, 3, [.shoulders]),  // smith shoulder press
    ]

    /// Indice per id.
    public static let byID: [String: CuratedExercise] = Dictionary(
        all.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Numero di esercizi selezionati.
    public static var count: Int { all.count }

    /// Righe con quello schema motorio.
    public static func entries(pattern: MovementPattern) -> [CuratedExercise] {
        all.filter { $0.pattern == pattern }
    }

    // MARK: - Risoluzione sulla libreria

    /// Risolve la selezione sulla libreria, scartando in silenzio gli id che non
    /// esistono (non dovrebbe succedere: è un check di `GymChecks`).
    public static func resolved(in library: some ExerciseSource) -> [ResolvedExercise] {
        all.compactMap { curated in
            guard let exercise = library.exercise(id: curated.id) else { return nil }
            return ResolvedExercise(curated: curated, exercise: exercise)
        }
    }

    /// Id della selezione che la libreria non conosce.
    public static func missingIDs(in library: some ExerciseSource) -> [String] {
        all.map(\.id).filter { library.exercise(id: $0) == nil }
    }

    // MARK: - Minimi di copertura

    /// Quanti esercizi servono almeno per ogni gruppo, con una data attrezzatura.
    ///
    /// Sono i numeri sotto i quali una scheda comincia a ripetersi: con 3 opzioni
    /// di petto non si costruiscono due giorni di spinta diversi. `GymChecks`
    /// li verifica a ogni build, così togliere un esercizio dalla tabella non
    /// può far scendere la copertura sotto la soglia senza accorgersene.
    public static let minimumPerGroup: [EquipmentClass: [MuscleGroup: Int]] = [
        .bodyweightBands: [
            .chest: 5, .back: 6, .shoulders: 5, .biceps: 3, .triceps: 4, .forearms: 2,
            .abs: 10, .quads: 4, .hamstrings: 3, .glutes: 5, .calves: 4, .cardio: 4,
        ],
        .dumbbellBench: [
            .chest: 8, .back: 8, .shoulders: 9, .biceps: 8, .triceps: 7, .forearms: 4,
            .abs: 12, .quads: 7, .hamstrings: 5, .glutes: 8, .calves: 6, .cardio: 4,
        ],
        .gym: [
            .chest: 14, .back: 16, .shoulders: 14, .biceps: 12, .triceps: 12, .forearms: 6,
            .abs: 14, .quads: 10, .hamstrings: 8, .glutes: 10, .calves: 9, .cardio: 8,
        ],
    ]
}
