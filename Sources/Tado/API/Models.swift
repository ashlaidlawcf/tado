import Foundation

struct Me: Decodable, Sendable {
    let name: String?
    let homes: [HomeRef]
}

struct HomeRef: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
}

enum ZoneType: String, Codable, Sendable {
    case heating = "HEATING"
    case hotWater = "HOT_WATER"
    case airConditioning = "AIR_CONDITIONING"
}

struct Zone: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let type: ZoneType
}

struct Temperature: Codable, Sendable, Hashable {
    let celsius: Double
}

struct ZoneSetting: Codable, Sendable, Hashable {
    let type: ZoneType
    let power: String          // "ON" / "OFF"
    let temperature: Temperature?

    var isOn: Bool { power == "ON" }
}

struct ZoneStatesResponse: Decodable, Sendable {
    let zoneStates: [String: ZoneState]
}

struct ZoneState: Decodable, Sendable, Hashable {
    let setting: ZoneSetting
    let overlayType: String?   // "MANUAL" when a manual override is active
    let sensorDataPoints: SensorData?
    let activityDataPoints: ActivityData?

    var hasOverlay: Bool { overlayType != nil }
    var insideTemperature: Double? { sensorDataPoints?.insideTemperature?.celsius }
    var humidity: Double? { sensorDataPoints?.humidity?.percentage }
    var heatingPower: Double? { activityDataPoints?.heatingPower?.percentage }

    struct SensorData: Decodable, Sendable, Hashable {
        let insideTemperature: Temperature?
        let humidity: Percentage?
    }

    struct ActivityData: Decodable, Sendable, Hashable {
        let heatingPower: Percentage?
    }

    struct Percentage: Decodable, Sendable, Hashable {
        let percentage: Double
    }
}

/// When a manual override should end.
enum OverlayTermination: Sendable {
    case manual                   // until changed
    case nextTimeBlock            // until the next schedule change
    case timer(seconds: Int)

    var json: [String: Any] {
        switch self {
        case .manual: ["typeSkillBasedApp": "MANUAL"]
        case .nextTimeBlock: ["typeSkillBasedApp": "NEXT_TIME_BLOCK"]
        case .timer(let seconds): ["typeSkillBasedApp": "TIMER", "durationInSeconds": seconds]
        }
    }
}
