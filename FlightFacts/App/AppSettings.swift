import Foundation
import SwiftUI

/// User preferences, persisted to UserDefaults. The API key is the one thing
/// that does *not* live here — it goes in the Keychain.
@Observable
final class AppSettings {

    static let shared = AppSettings()

    var notificationsEnabled: Bool { didSet { save(notificationsEnabled, "notif") } }
    var notifyPOI: Bool            { didSet { save(notifyPOI, "notifPOI") } }
    var notifyAdvice: Bool         { didSet { save(notifyAdvice, "notifAdvice") } }
    var onlineEnrichment: Bool     { didSet { save(onlineEnrichment, "online") } }
    var aiFactsEnabled: Bool       { didSet { save(aiFactsEnabled, "ai") } }
    var useImperial: Bool          { didSet { save(useImperial, "imperial") } }
    var mapStyleRaw: String        { didSet { save(mapStyleRaw, "mapStyle") } }
    var hapticsEnabled: Bool       { didSet { save(hapticsEnabled, "haptics") } }

    /// 3D terrain mesh on the map. Off by default — it's the single biggest
    /// cause of slow tile loading, and at cruise the relief isn't visible anyway.
    var use3DTerrain: Bool         { didSet { save(use3DTerrain, "terrain3D") } }
    /// Hold the screen awake while a flight is active.
    var keepScreenAwake: Bool      { didSet { save(keepScreenAwake, "keepAwake") } }
    /// Lock Screen / Dynamic Island live view of the current fact.
    var liveActivityEnabled: Bool  { didSet { save(liveActivityEnabled, "liveActivity") } }
    /// How chatty the feed is.
    var factDensityRaw: String     { didSet { save(factDensityRaw, "factDensity") } }

    enum FactDensity: String, CaseIterable, Identifiable {
        case relaxed, standard, chatty
        var id: String { rawValue }

        var label: String {
            switch self {
            case .relaxed:  return "Relaxed"
            case .standard: return "Standard"
            case .chatty:   return "Chatty"
            }
        }

        var blurb: String {
            switch self {
            case .relaxed:  return "Landmarks and the important alerts only."
            case .standard: return "A steady stream — roughly a fact every few minutes."
            case .chatty:   return "Everything, as often as there's something to say."
            }
        }

        /// Seconds of flight time between POI sweeps.
        var poiInterval: TimeInterval {
            switch self {
            case .relaxed: return 45
            case .standard: return 20
            case .chatty: return 12
            }
        }

        /// How many POIs may be called out in one sweep.
        var poiBatch: Int {
            switch self {
            case .relaxed: return 1
            case .standard: return 2
            case .chatty: return 3
            }
        }

        /// Seconds of flight time between filler items at cruise.
        ///
        /// Paced against a finite pool — roughly 60 hangar-talk items — so even
        /// `chatty` on a long flight doesn't run dry halfway and go quiet.
        var fillerInterval: TimeInterval {
            switch self {
            case .relaxed: return 900
            case .standard: return 400
            case .chatty: return 220
            }
        }
    }

    var factDensity: FactDensity {
        get { FactDensity(rawValue: factDensityRaw) ?? .standard }
        set { factDensityRaw = newValue.rawValue }
    }

    /// Playback multiplier for demo flights.
    var demoSpeed: Double          { didSet { save(demoSpeed, "demoSpeed") } }

    enum MapStyleChoice: String, CaseIterable, Identifiable {
        case hybrid, imagery, standard
        var id: String { rawValue }
        var label: String {
            switch self {
            case .hybrid:   return "Hybrid"
            case .imagery:  return "Satellite"
            case .standard: return "Map"
            }
        }
    }

    var mapStyle: MapStyleChoice {
        get { MapStyleChoice(rawValue: mapStyleRaw) ?? .hybrid }
        set { mapStyleRaw = newValue.rawValue }
    }

    var hasAPIKey: Bool { KeychainStore.apiKey?.isEmpty == false }

    private let d = UserDefaults.standard

    private init() {
        // Free function, not a method — nothing on `self` is initialised yet.
        let store = UserDefaults.standard
        func bool(_ key: String, default def: Bool) -> Bool {
            store.object(forKey: key) == nil ? def : store.bool(forKey: key)
        }
        notificationsEnabled = bool("notif", default: true)
        notifyPOI = bool("notifPOI", default: true)
        notifyAdvice = bool("notifAdvice", default: true)
        onlineEnrichment = bool("online", default: true)
        aiFactsEnabled = bool("ai", default: false)
        useImperial = bool("imperial", default: true)
        hapticsEnabled = bool("haptics", default: true)
        use3DTerrain = bool("terrain3D", default: false)
        keepScreenAwake = bool("keepAwake", default: true)
        liveActivityEnabled = bool("liveActivity", default: true)
        factDensityRaw = store.string(forKey: "factDensity") ?? FactDensity.standard.rawValue
        mapStyleRaw = store.string(forKey: "mapStyle") ?? MapStyleChoice.hybrid.rawValue
        demoSpeed = store.object(forKey: "demoSpeed") == nil ? 60 : store.double(forKey: "demoSpeed")
    }

    private func save(_ value: Any, _ key: String) { d.set(value, forKey: key) }

    func setAPIKey(_ key: String?) {
        KeychainStore.apiKey = key
    }
}
