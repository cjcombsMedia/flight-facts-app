import Foundation

/// Aviation history: date-matched "on this day" entries plus a rotating pool of
/// hangar talk for the long quiet stretches at cruise.
final class AviationHistory {

    static let shared = AviationHistory()

    struct OnThisDay: Codable {
        var month: Int
        var day: Int
        var year: Int
        var title: String
        var text: String
    }

    struct HangarTalk: Codable {
        var title: String
        var text: String
    }

    private struct Corpus: Codable {
        var onThisDay: [OnThisDay]
        var hangarTalk: [HangarTalk]
    }

    private var corpus = Corpus(onThisDay: [], hangarTalk: [])
    private var servedTalk = Set<Int>()

    private init() {
        guard let url = Bundle.main.url(forResource: "aviation_history", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Corpus.self, from: data) else {
            assertionFailure("aviation_history.json missing or malformed")
            return
        }
        corpus = decoded
    }

    /// Anniversaries falling on `date`.
    func anniversaries(on date: Date = Date()) -> [OnThisDay] {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day else { return [] }
        return corpus.onThisDay.filter { $0.month == m && $0.day == d }
    }

    /// Anniversaries within `window` days either side — so a long flight on the
    /// 16th still gets to mention Kitty Hawk on the 17th.
    func nearbyAnniversaries(on date: Date = Date(), window: Int = 2) -> [OnThisDay] {
        let cal = Calendar.current
        var out: [OnThisDay] = []
        for offset in -window...window {
            guard let d = cal.date(byAdding: .day, value: offset, to: date) else { continue }
            out.append(contentsOf: anniversaries(on: d))
        }
        // De-dupe while preserving order.
        var seen = Set<String>()
        return out.filter { seen.insert($0.title).inserted }
    }

    /// Next unserved hangar-talk item, or nil once the pool is exhausted.
    ///
    /// Deliberately does *not* wrap. On a long flight at high chattiness there
    /// are more filler slots than there are facts, and hearing the same one
    /// twice reads worse than a quiet stretch — so we go silent instead and let
    /// the other producers (POIs, sky, milestones) carry it.
    func nextHangarTalk() -> HangarTalk? {
        guard !corpus.hangarTalk.isEmpty else { return nil }
        let remaining = corpus.hangarTalk.indices.filter { !servedTalk.contains($0) }
        guard let pick = remaining.randomElement() else { return nil }
        servedTalk.insert(pick)
        return corpus.hangarTalk[pick]
    }

    /// How much of the pool is left — lets the engine pace itself.
    var hangarTalkRemaining: Int {
        max(0, corpus.hangarTalk.count - servedTalk.count)
    }

    func resetRotation() { servedTalk.removeAll() }

    /// How many years ago an anniversary was, relative to `date`.
    func yearsAgo(_ entry: OnThisDay, from date: Date = Date()) -> Int {
        let year = Calendar.current.component(.year, from: date)
        return max(0, year - entry.year)
    }
}
