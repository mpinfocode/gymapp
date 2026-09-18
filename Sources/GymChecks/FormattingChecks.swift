import Foundation
import GymCore

/// Verifica della formattazione italiana dei numeri e della coerenza dei testi
/// che GymCore produce per la UI (SPEC §5: virgola decimale, percentuali attaccate,
/// segno meno ASCII, mai trattini lunghi).
@MainActor
func runFormattingChecks(_ h: Harness) {

    // MARK: Numeri all'italiana

    h.section("formattazione · ItalianNumberFormat")

    h.check("virgola decimale", ItalianNumberFormat.number(82.5) == "82,5")
    h.check("niente zeri inutili", ItalianNumberFormat.number(12.0) == "12")
    h.check("zeri finali tolti anche con più decimali", ItalianNumberFormat.number(12.50, fractionDigits: 3) == "12,5")
    h.check("arrotondamento al decimale richiesto", ItalianNumberFormat.number(14.26) == "14,3")
    h.check("zero decimali", ItalianNumberFormat.number(82.4, fractionDigits: 0) == "82")
    h.check("migliaia con il punto", ItalianNumberFormat.number(12_480) == "12.480")
    h.check("migliaia e decimali insieme", ItalianNumberFormat.number(12_480.5) == "12.480,5")
    h.check("milioni raggruppati a tre a tre", ItalianNumberFormat.integer(1_234_567) == "1.234.567")
    h.check("sotto le mille niente separatore", ItalianNumberFormat.integer(980) == "980")
    h.check("raggruppamento disattivabile", ItalianNumberFormat.number(12_480, grouping: false) == "12480")
    h.check("intero da Int", ItalianNumberFormat.integer(12_480) == "12.480")

    h.check("segno meno ASCII", ItalianNumberFormat.number(-1.2) == "-1,2")
    h.check("il meno è attaccato al numero", !ItalianNumberFormat.number(-1.2).contains("- "))
    h.check("mai -0", ItalianNumberFormat.number(-0.001) == "0")
    h.check("mai -0 nemmeno con zero decimali", ItalianNumberFormat.number(-0.4, fractionDigits: 0) == "0")
    h.check("zero resta zero", ItalianNumberFormat.number(0) == "0")
    h.check("valore non finito non rompe il testo", ItalianNumberFormat.number(.nan) == "0")

    h.check("segno esplicito sui positivi", ItalianNumberFormat.signed(1.5) == "+1,5")
    h.check("segno esplicito sui negativi", ItalianNumberFormat.signed(-1.5) == "-1,5")
    h.check("lo zero non prende il segno", ItalianNumberFormat.signed(0) == "0")

    h.check("percentuale attaccata", ItalianNumberFormat.percent(16.4) == "16,4%")
    h.check("percentuale negativa", ItalianNumberFormat.percent(-1.2) == "-1,2%")
    h.check("percentuale con segno", ItalianNumberFormat.signedPercent(16.4) == "+16,4%")
    h.check("niente spazio prima del simbolo di percentuale", !ItalianNumberFormat.percent(16.4).contains(" "))

    h.check("misura con unità", ItalianNumberFormat.measurement(82.5, unit: "kg") == "82,5 kg")
    h.check("misura in percentuale attaccata", ItalianNumberFormat.measurement(16.4, unit: "%") == "16,4%")
    h.check("misura senza unità", ItalianNumberFormat.measurement(82.5, unit: "") == "82,5")
    h.check("conversione dei punti decimali", ItalianNumberFormat.commaDecimals("82.5 kg") == "82,5 kg")
    h.check("separatori dichiarati",
            ItalianNumberFormat.decimalSeparator == "," && ItalianNumberFormat.groupingSeparator == "."
            && ItalianNumberFormat.minusSign == "-")

    // MARK: Testi prodotti da GymCore

    h.section("formattazione · testi per la UI")

    h.check("carico in kg", WeightUnit.kg.format(kilograms: 82.5) == "82,5 kg")
    h.check("carico intero senza decimali", WeightUnit.kg.format(kilograms: 100) == "100 kg")
    h.check("il carico non separa le migliaia (resta modificabile a mano)",
            WeightUnit.kg.format(kilograms: 1_200, includeSymbol: false) == "1200")
    h.check("riepilogo della voce di scheda",
            PlanItem(exerciseID: "0025", targetSets: 4, measure: .reps(min: 6, max: 8), targetWeightKg: 82.5).summary()
            == "4 × 6-8 · 82,5 kg")
    h.check("metrica corporea in kg", BodyMetricKind.weight.format(78.45) == "78,5 kg")
    h.check("metrica corporea in cm", BodyMetricKind.measure(.waist).format(83) == "83 cm")
    h.check("metrica corporea in percentuale", BodyMetricKind.bodyFat.format(16.42) == "16,4%")
    h.check("volume con le migliaia separate", Stats.formatVolume(12_480) == "12,5k kg")
    h.check("volume sotto la soglia di abbreviazione", Stats.formatVolume(4_820) == "4.820 kg")

    let entries = [
        BodyEntry(date: Fixtures.date(2025, 3, 1), weightKg: 79.2, bodyFatPct: 17.6, measurementsCm: [.waist: 85]),
        BodyEntry(date: Fixtures.date(2025, 4, 1), weightKg: 78.0, bodyFatPct: 16.4, measurementsCm: [.waist: 83]),
    ]
    if let weight = Stats.bodyChange(of: .weight, in: entries, since: Fixtures.date(2025, 3, 1)),
       let fat = Stats.bodyChange(of: .bodyFat, in: entries, since: Fixtures.date(2025, 3, 1)),
       let waist = Stats.bodyChange(of: .measure(.waist), in: entries, since: Fixtures.date(2025, 3, 1)) {
        h.check("variazione del peso con la virgola", weight.deltaText() == "-1,2 kg")
        h.check("variazione percentuale attaccata al numero", fat.deltaText() == "-1,2%")
        h.check("nessuno spazio prima della percentuale", !fat.deltaText().contains(" %"))
        h.check("variazione in cm", waist.deltaText() == "-2 cm")
        h.check("percentuale di variazione formattata", weight.percentChangeText() == "-1,5%")
        h.check("nessuna percentuale se il riferimento è zero",
                Stats.BodyChange(
                    metric: .weight,
                    start: Stats.BodyPoint(date: Fixtures.date(2025, 3, 1), value: 0),
                    latest: Stats.BodyPoint(date: Fixtures.date(2025, 4, 1), value: 1)
                ).percentChangeText() == nil)
    } else {
        h.fail("variazioni corporee non calcolate")
    }

    // Nessun testo di presentazione deve contenere punti decimali o trattini lunghi.
    let item = PlanItem(exerciseID: "0025", targetSets: 3, measure: .reps(min: 6, max: 8))
    let maxed = WorkoutSession(
        name: "x",
        startedAt: Fixtures.date(2025, 4, 1),
        endedAt: Fixtures.date(2025, 4, 1, 13),
        entries: [SessionEntry(exerciseID: "0025", sets: (0..<3).map { _ in
            SetLog(kind: .normal, weightKg: 12.5, reps: 8, completedAt: Fixtures.date(2025, 4, 1))
        })]
    )
    var uiTexts: [String] = [
        WeightUnit.kg.format(kilograms: 82.5),
        WeightUnit.lb.format(kilograms: 100),
        BodyMetricKind.bodyFat.format(16.42),
        BodyMetricKind.weight.format(78.45),
        Stats.formatVolume(12_480),
        item.summary(),
    ]
    for equipment in ["barbell", "dumbbell", "kettlebell", "cable", "leverage machine"] {
        if let suggestion = Stats.progressionSuggestion(for: item, lastSession: maxed, equipment: equipment) {
            uiTexts.append(suggestion.reason)
        } else {
            h.fail("nessun suggerimento con attrezzo \(equipment)")
        }
    }
    if let previous = Stats.previousPerformance(for: "0025", in: [maxed]) {
        uiTexts.append(previous.text(forSetAt: 0) ?? "")
    }
    let withDecimalPoint = uiTexts.filter { $0.range(of: "[0-9]\\.[0-9]", options: .regularExpression) != nil }
    h.check("nessun punto decimale nei testi per la UI: \(withDecimalPoint)", withDecimalPoint.isEmpty)
    let withLongDash = uiTexts.filter { $0.contains("\u{2014}") || $0.contains("\u{2013}") || $0.contains("\u{2212}") }
    h.check("nessun trattino lungo né meno tipografico: \(withLongDash)", withLongDash.isEmpty)
}
