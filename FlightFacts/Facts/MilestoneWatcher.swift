import Foundation

/// Fires one-shot "by the numbers" facts as the flight crosses thresholds.
///
/// Everything here is derived from telemetry alone, so it works with no network
/// and no landmark anywhere near you — which matters over oceans and deserts,
/// where the map has nothing to say for hours.
final class MilestoneWatcher {

    private var fired = Set<String>()
    private var flightStart: Date?

    func reset() {
        fired.removeAll()
        flightStart = nil
    }

    func noteFlightStart(_ date: Date) {
        if flightStart == nil { flightStart = date }
    }

    /// Returns any milestones newly crossed by this sample.
    func check(_ s: FlightSample, phase: FlightPhase) -> [Bubble] {
        var out: [Bubble] = []

        func once(_ key: String, _ make: () -> Bubble) {
            guard !fired.contains(key) else { return }
            fired.insert(key)
            out.append(make())
        }

        let ft = s.alt * 3.280839895

        // MARK: Altitude milestones

        if ft >= 10_000 {
            once("alt-10k") {
                Bubble(kind: .stat, title: "Ten thousand feet",
                       body: "You are above the altitude where most small aircraft fly, and above the level where the crew can take their seatbelts off.",
                       detail: ["Outside it is around 23°F.",
                                "This is the altitude the FAA's sterile-cockpit rule ends — below it, no non-essential chatter on the flight deck."])
            }
        }

        if ft >= 29_032 {
            once("alt-everest") {
                Bubble(kind: .milestone, title: "Higher than Everest",
                       body: "You just passed 29,032 feet. You are now above the summit of the highest mountain on Earth, eating a snack.",
                       detail: ["Climbers spend weeks acclimatising to reach this altitude. You did it in about twenty minutes.",
                                "Outside your window the air is about -58°F and roughly a third of sea-level pressure."],
                       priority: .high)
            }
        }

        if ft >= 35_000 {
            once("alt-35k") {
                Bubble(kind: .stat, title: "Flight level 350",
                       body: "Above 18,000 feet everyone sets their altimeter to the same standard pressure, so altitudes become 'flight levels' — this one is FL350.",
                       detail: ["It means every aircraft in the system is measuring altitude the same way, so 1,000 feet of separation really is 1,000 feet."])
            }
        }

        if ft >= 40_000 {
            once("alt-40k") {
                Bubble(kind: .stat, title: "Forty thousand feet",
                       body: "Only about a quarter of the atmosphere's mass is still above you. The sky out that window is noticeably darker than it is from the ground.",
                       detail: ["Time of useful consciousness at this altitude without oxygen is 15 to 20 seconds. That is what the masks are for."])
            }
        }

        // MARK: Speed

        if s.spd > 240 && s.alt > 9_000 {
            once("mach") {
                Bubble(kind: .stat, title: Units.mach(s.spd, altitudeM: s.alt),
                       body: "You are travelling at \(Units.mph(s.spd)) over the ground — about a mile every \(self.mileSeconds(s.spd)) seconds.",
                       detail: ["Airliners cruise just below the speed of sound. Push much past Mach 0.85 and shockwaves start forming over the wing, and drag climbs sharply.",
                                "Concorde solved that with a delta wing and afterburners, and burned roughly three times the fuel per passenger to do it."])
            }
        }

        // MARK: Distance

        for mark in [500.0, 1_000, 2_000, 3_000, 5_000] {
            let km = s.odo / 1_000
            if km >= mark {
                once("dist-\(Int(mark))") {
                    Bubble(kind: .milestone, title: "\(Int(mark)) km down",
                           body: "That is \(Units.miles(mark * 1_000)) since you started moving.",
                           detail: ["At your current speed you are covering about \(Units.km(s.spd * 60)) every minute."])
                }
            }
        }

        // MARK: Time aloft

        if let start = flightStart, phase.isAirborne {
            let hours = Int(s.t.timeIntervalSince(start) / 3_600)
            if hours >= 1 {
                once("hours-\(hours)") {
                    Bubble(kind: .advice, title: "\(hours) hour\(hours == 1 ? "" : "s") in the air",
                           body: hours >= 3
                               ? "Good moment to stand up, walk the aisle and drink some water. Cabin humidity is running around 15%."
                               : "Worth a stretch and a glass of water — the air up here is drier than most deserts.",
                           detail: ["Moving your legs every hour or two meaningfully reduces the risk of clots on long flights.",
                                    "Ankle circles and calf raises in your seat work if the belt sign is on."])
                }
            }
        }

        // MARK: Outside conditions

        if s.alt > 10_000 {
            once("outside-air") {
                let c = self.isaTemp(altitudeM: s.alt)
                return Bubble(kind: .stat, title: "It is \(Int(c))°C outside",
                              body: "That is \(Int(c * 9 / 5 + 32))°F, three feet away on the other side of the window.",
                              detail: ["Standard atmosphere cools about 2°C per 1,000 feet until roughly 36,000 feet, then holds steady at about -56°C.",
                                       "Jet fuel freezes around -47°C, so on long polar flights the crew actually monitor fuel temperature."])
            }
        }

        return out
    }

    private func mileSeconds(_ mps: Double) -> Int {
        max(1, Int((1_609.344 / max(1, mps)).rounded()))
    }

    /// International Standard Atmosphere temperature, °C.
    private func isaTemp(altitudeM: Double) -> Double {
        altitudeM >= 11_000 ? -56.5 : 15.0 - 0.0065 * altitudeM
    }
}
