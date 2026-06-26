import Foundation

enum ActivityType: String, CaseIterable, Codable {
    case hiking
    case cycling
    case running
    case waterSports = "water_sports"
    case stargazing
    case gardening
    case fishing
    case picnic
    case golf
    case tennis

    var displayName: String {
        switch self {
        case .hiking: return String(localized: "activity.hiking", defaultValue: "Hiking")
        case .cycling: return String(localized: "activity.cycling", defaultValue: "Cycling")
        case .running: return String(localized: "activity.running", defaultValue: "Running")
        case .waterSports: return String(localized: "activity.waterSports", defaultValue: "Water Sports")
        case .stargazing: return String(localized: "activity.stargazing", defaultValue: "Stargazing")
        case .gardening: return String(localized: "activity.gardening", defaultValue: "Gardening")
        case .fishing: return String(localized: "activity.fishing", defaultValue: "Fishing")
        case .picnic: return String(localized: "activity.picnic", defaultValue: "Picnic")
        case .golf: return String(localized: "activity.golf", defaultValue: "Golf")
        case .tennis: return String(localized: "activity.tennis", defaultValue: "Tennis")
        }
    }
}

enum SuitabilityLevel: String, CaseIterable {
    case unsuitable, poor, fair, good, excellent

    var displayName: String {
        switch self {
        case .unsuitable: return String(localized: "suitability.unsuitable", defaultValue: "Unsuitable")
        case .poor: return String(localized: "suitability.poor", defaultValue: "Poor")
        case .fair: return String(localized: "suitability.fair", defaultValue: "Fair")
        case .good: return String(localized: "suitability.good", defaultValue: "Good")
        case .excellent: return String(localized: "suitability.excellent", defaultValue: "Excellent")
        }
    }

    var color: String {
        switch self {
        case .unsuitable: return "red"
        case .poor: return "orange"
        case .fair: return "yellow"
        case .good: return "lightGreen"
        case .excellent: return "green"
        }
    }
}

struct Activity: Codable, Identifiable, Equatable {
    var id: UUID
    var type: ActivityType
    var name: String
    var minTemperature: Double
    var maxTemperature: Double
    var maxWindSpeed: Double
    var maxWindGust: Double
    var minVisibility: Double
    var maxUVIndex: Int
    var avoidRain: Bool
    var avoidSnow: Bool
    var avoidFog: Bool
    var avoidStorm: Bool

    init(
        id: UUID = UUID(),
        type: ActivityType,
        name: String? = nil,
        minTemperature: Double = 0,
        maxTemperature: Double = 35,
        maxWindSpeed: Double = 30,
        maxWindGust: Double = 50,
        minVisibility: Double = 1,
        maxUVIndex: Int = 11,
        avoidRain: Bool = false,
        avoidSnow: Bool = false,
        avoidFog: Bool = false,
        avoidStorm: Bool = true
    ) {
        self.id = id
        self.type = type
        self.name = name ?? type.displayName
        self.minTemperature = minTemperature
        self.maxTemperature = maxTemperature
        self.maxWindSpeed = maxWindSpeed
        self.maxWindGust = maxWindGust
        self.minVisibility = minVisibility
        self.maxUVIndex = maxUVIndex
        self.avoidRain = avoidRain
        self.avoidSnow = avoidSnow
        self.avoidFog = avoidFog
        self.avoidStorm = avoidStorm
    }

    static var defaults: [Activity] {
        [
            Activity(
                type: .hiking,
                minTemperature: -5,
                maxTemperature: 30,
                maxWindSpeed: 25,
                maxWindGust: 40,
                minVisibility: 2,
                maxUVIndex: 11,
                avoidRain: true,
                avoidSnow: false,
                avoidFog: true,
                avoidStorm: true
            ),
            Activity(
                type: .cycling,
                minTemperature: 5,
                maxTemperature: 28,
                maxWindSpeed: 20,
                maxWindGust: 35,
                minVisibility: 3,
                avoidRain: true,
                avoidSnow: true,
                avoidFog: true,
                avoidStorm: true
            ),
            Activity(
                type: .running,
                minTemperature: 5,
                maxTemperature: 25,
                maxWindSpeed: 25,
                maxWindGust: 45,
                minVisibility: 1,
                maxUVIndex: 8,
                avoidRain: false,
                avoidSnow: true,
                avoidFog: false,
                avoidStorm: true
            ),
            Activity(
                type: .waterSports,
                minTemperature: 10,
                maxTemperature: 32,
                maxWindSpeed: 15,
                maxWindGust: 30,
                minVisibility: 5,
                maxUVIndex: 11,
                avoidRain: false,
                avoidSnow: true,
                avoidFog: true,
                avoidStorm: true
            ),
            Activity(
                type: .stargazing,
                minTemperature: -10,
                maxTemperature: 20,
                maxWindSpeed: 15,
                maxWindGust: 30,
                minVisibility: 10,
                maxUVIndex: 0,
                avoidRain: true,
                avoidSnow: false,
                avoidFog: true,
                avoidStorm: true
            ),
            Activity(
                type: .gardening,
                minTemperature: 5,
                maxTemperature: 30,
                maxWindSpeed: 20,
                maxWindGust: 40,
                minVisibility: 1,
                maxUVIndex: 8,
                avoidRain: false,
                avoidSnow: true,
                avoidFog: false,
                avoidStorm: true
            ),
            Activity(
                type: .fishing,
                minTemperature: 0,
                maxTemperature: 30,
                maxWindSpeed: 20,
                maxWindGust: 40,
                minVisibility: 2,
                avoidRain: false,
                avoidSnow: false,
                avoidFog: true,
                avoidStorm: true
            ),
            Activity(
                type: .picnic,
                minTemperature: 10,
                maxTemperature: 28,
                maxWindSpeed: 15,
                maxWindGust: 30,
                minVisibility: 1,
                maxUVIndex: 8,
                avoidRain: true,
                avoidSnow: true,
                avoidFog: false,
                avoidStorm: true
            ),
            Activity(
                type: .golf,
                minTemperature: 5,
                maxTemperature: 28,
                maxWindSpeed: 20,
                maxWindGust: 35,
                minVisibility: 3,
                maxUVIndex: 9,
                avoidRain: true,
                avoidSnow: true,
                avoidFog: false,
                avoidStorm: true
            ),
            Activity(
                type: .tennis,
                minTemperature: 10,
                maxTemperature: 28,
                maxWindSpeed: 15,
                maxWindGust: 30,
                minVisibility: 2,
                maxUVIndex: 8,
                avoidRain: true,
                avoidSnow: true,
                avoidFog: true,
                avoidStorm: true
            )
        ]
    }
}

struct ActivitySuitability: Equatable {
    let activity: Activity
    let suitability: SuitabilityLevel
    let warnings: [String]
    let recommendations: [String]
}

enum ActivityStorage {
    private static let userActivitiesKey = "praeventus_user_activities"

    static func saveActivities(_ activities: [Activity]) {
        do {
            let encoded = try JSONEncoder().encode(activities)
            UserDefaults.standard.set(encoded, forKey: userActivitiesKey)
        } catch {
            print("Error saving activities: \(error)")
        }
    }

    static func loadActivities() -> [Activity] {
        guard let data = UserDefaults.standard.data(forKey: userActivitiesKey) else {
            return Activity.defaults
        }
        do {
            return try JSONDecoder().decode([Activity].self, from: data)
        } catch {
            print("Error loading activities: \(error)")
            return Activity.defaults
        }
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: userActivitiesKey)
    }
}
