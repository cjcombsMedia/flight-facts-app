import Foundation

/// Turns phase transitions into the cabin-crew nudges: belts, trays, seat backs,
/// and the descent warning that actually gives you time to react.
///
/// The valuable one is `.descent`. Top of descent happens roughly 100 miles and
/// 25 minutes before landing — well before the crew makes the announcement — so
/// this is genuinely useful information rather than a restatement of the PA.
final class CabinAdvisor {

    private var delivered = Set<String>()
    private var descentAnnouncedAt: Date?

    func reset() {
        delivered.removeAll()
        descentAnnouncedAt = nil
        choppySamples = 0
    }

    /// Advice for a confirmed phase transition, if any.
    func advice(entering phase: FlightPhase, from previous: FlightPhase, sample: FlightSample) -> Bubble? {
        let key = "\(previous.rawValue)->\(phase.rawValue)"
        // Allow repeats of nothing except a second descent after a level-off.
        guard !delivered.contains(key) || phase == .descent else { return nil }
        delivered.insert(key)

        switch phase {

        case .taxi where !previous.isAirborne:
            return Bubble(
                kind: .advice, title: "We're moving",
                body: "Seatbelt low and tight, tray table up, bag fully under the seat in front.",
                detail: ["Taxi is statistically one of the more eventful phases — hard braking for a runway incursion is a real thing.",
                         "Keep the window shade up. The crew needs to be able to see out."],
                priority: .normal)

        case .takeoffRoll:
            return Bubble(
                kind: .advice, title: "Here we go",
                body: "Takeoff roll. Sit back — you're about to accelerate to around 160 mph in half a minute.",
                detail: ["Somewhere in the next 30 seconds the crew passes V1: the speed after which they will take the aircraft into the air no matter what fails.",
                         "The clunk shortly after liftoff is the landing gear coming up."],
                priority: .high)

        case .climb where previous == .takeoffRoll || previous == .taxi:
            return Bubble(
                kind: .advice, title: "Wheels up",
                body: "Stay belted until the sign goes off — the first few minutes are the steepest part of the climb.",
                detail: ["That reduction in engine noise a couple of minutes in is normal thrust reduction for noise abatement, not a problem.",
                         "You'll feel the nose lower as the flaps come up in stages."],
                priority: .high)

        case .cruise where previous == .climb:
            return Bubble(
                kind: .advice, title: "Levelled off",
                body: "Cruise altitude. The belt sign usually comes off about now — good time to stretch, and drink something.",
                detail: ["Cabin humidity up here runs 10–20%. Dehydration is most of what people call jet lag fatigue.",
                         "Keep the belt loosely fastened when seated anyway. Clear-air turbulence gives no warning at all."],
                priority: .normal)

        case .descent:
            // Don't re-fire on every wobble; once every 20 minutes at most.
            if let last = descentAnnouncedAt, sample.t.timeIntervalSince(last) < 1_200 { return nil }
            descentAnnouncedAt = sample.t
            return Bubble(
                kind: .advice, title: "Starting down",
                body: "Top of descent. Tray tables up, seat backs forward, belt fastened, and finish that drink.",
                detail: ["From here it's typically 20 to 30 minutes and around 100 miles to the runway.",
                         "Swallow, yawn or chew — the pressure change on descent is faster than on climb and that's when ears complain.",
                         "Bags need to be under the seat in front or in the bin, not by your feet in the aisle."],
                priority: .high)

        case .approach:
            return Bubble(
                kind: .advice, title: "On approach",
                body: "Final stretch. Devices secured, headphones off for the landing, belt tight and low across your hips.",
                detail: ["The rumbling and the pitch changes are flaps and gear coming down on schedule.",
                         "Cabin lights dim for a night landing so your eyes are already dark-adapted if anything goes wrong."],
                priority: .high)

        case .landed:
            return Bubble(
                kind: .advice, title: "Welcome down",
                body: "Stay seated with your belt on until the sign goes off — the aircraft still has to taxi, and it brakes harder than you'd think.",
                detail: ["That roar right after touchdown is thrust reversers, not something breaking.",
                         "Check the seat pocket. It is the single most common place to leave a passport."],
                priority: .high)

        default:
            return nil
        }
    }

    /// Consecutive samples that looked like turbulence.
    private var choppySamples = 0

    /// Ambient, condition-based nudges that aren't tied to a phase change.
    func ambientAdvice(for s: FlightSample, phase: FlightPhase) -> Bubble? {
        // Turbulence needs to be *sustained*, and the phone not being turned
        // over in someone's hand. Picking the phone up produces a big
        // acceleration spike too — but with lots of rotation, and only briefly.
        let shaking = (s.rms ?? 0) > 0.09 && (s.gyro ?? 0) < 0.6
        choppySamples = phase.isAirborne && shaking ? choppySamples + 1 : 0
        guard choppySamples >= 15, !delivered.contains("turbulence") else { return nil }
        delivered.insert("turbulence")

        return Bubble(
            kind: .advice, title: "Bit of chop",
            body: "The accelerometer is picking up real turbulence. Belt on, and put the drink down for a minute.",
            detail: ["The wings are certified to about 2.5 g. Ordinary turbulence rarely gets past 1.3.",
                     "Almost all turbulence injuries are to people who weren't wearing a belt."],
            priority: .normal)
    }
}
