// ============================================================================
// CareFlow Watch — Shared Data Models
// ============================================================================
// iOS 앱과 watchOS 앱이 공유하는 데이터 모델
// 메니에르병 환자의 일상 증상 관리 (어지럼증, 이명, 스트레스)
// ============================================================================

import Foundation

// MARK: - 어지럼증 심각도

enum DizzinessSeverity: String, Codable, CaseIterable {
    case none     = "none"
    case mild     = "mild"
    case moderate = "moderate"
    case severe   = "severe"

    var emoji: String {
        switch self {
        case .none:     return "🟢"
        case .mild:     return "🟡"
        case .moderate: return "🟠"
        case .severe:   return "🔴"
        }
    }

    var label: String {
        switch self {
        case .none:     return "정상"
        case .mild:     return "주의"
        case .moderate: return "감지됨"
        case .severe:   return "즉시 대응"
        }
    }

    var nandaType: String {
        switch self {
        case .none:     return "Readiness for enhanced balance"
        case .mild:     return "Risk for falls"
        case .moderate: return "Actual impaired balance Related To vestibular input"
        case .severe:   return "PC: Vestibular disorder complication"
        }
    }
}

// MARK: - 음성 데시벨 레벨

enum VoiceLevel: String, Codable, CaseIterable {
    case quiet    = "quiet"     // < 60 dB
    case normal   = "normal"    // 60~70 dB
    case loud     = "loud"      // 70~80 dB
    case veryLoud = "very_loud" // 80+ dB

    var emoji: String {
        switch self {
        case .quiet:    return "🔇"
        case .normal:   return "🔈"
        case .loud:     return "🔉"
        case .veryLoud: return "🔊"
        }
    }

    var label: String {
        switch self {
        case .quiet:    return "조용"
        case .normal:   return "보통"
        case .loud:     return "다소 큼"
        case .veryLoud: return "매우 큼"
        }
    }
}

struct VoiceAlertRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let peakDecibel: Double
    let duration: TimeInterval
    let voiceLevel: VoiceLevel

    init(peakDecibel: Double, duration: TimeInterval, voiceLevel: VoiceLevel) {
        self.id = UUID()
        self.timestamp = Date()
        self.peakDecibel = peakDecibel
        self.duration = duration
        self.voiceLevel = voiceLevel
    }
}

// MARK: - 센서 데이터

struct GyroscopeData: Codable {
    let x: Double
    let y: Double
    let z: Double

    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }
}

struct AccelerometerData: Codable {
    let x: Double
    let y: Double
    let z: Double

    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }

    var tilt: Double {
        let mag = magnitude
        guard mag > 0 else { return 0 }
        return acos(abs(z) / mag) * (180.0 / .pi)
    }
}

// MARK: - 자세

enum Posture: String, Codable {
    case unknown  = "unknown"
    case lying    = "lying"
    case sitting  = "sitting"
    case standing = "standing"
    case walking  = "walking"

    var emoji: String {
        switch self {
        case .unknown:  return "❓"
        case .lying:    return "🛌"
        case .sitting:  return "🪑"
        case .standing: return "🧍"
        case .walking:  return "🚶"
        }
    }

    var label: String {
        switch self {
        case .unknown:  return "알 수 없음"
        case .lying:    return "누워있음"
        case .sitting:  return "앉아있음"
        case .standing: return "서있음"
        case .walking:  return "걷는 중"
        }
    }
}

// MARK: - 하루 유형

enum DayType: String, Codable, CaseIterable {
    case normal    = "normal"
    case busy      = "busy"
    case rest      = "rest"
    case sick      = "sick"
    case exercise  = "exercise"

    var emoji: String {
        switch self {
        case .normal:   return "📅"
        case .busy:     return "🏃"
        case .rest:     return "😴"
        case .sick:     return "🤒"
        case .exercise: return "💪"
        }
    }

    var label: String {
        switch self {
        case .normal:   return "보통"
        case .busy:     return "바쁜 날"
        case .rest:     return "휴식"
        case .sick:     return "컨디션 나쁨"
        case .exercise: return "운동"
        }
    }
}

// MARK: - 시간대

enum TimeSegment: String, Codable, CaseIterable {
    case wakeUp       = "wake_up"
    case earlyMorning = "early_morning"
    case morning      = "morning"
    case afternoon    = "afternoon"
    case evening      = "evening"
    case night        = "night"
    case bedtime      = "bedtime"

    var emoji: String {
        switch self {
        case .wakeUp:       return "⏰"
        case .earlyMorning: return "🌅"
        case .morning:      return "☀️"
        case .afternoon:    return "🌤️"
        case .evening:      return "🌆"
        case .night:        return "🌙"
        case .bedtime:      return "🛏️"
        }
    }

    var label: String {
        switch self {
        case .wakeUp:       return "기상"
        case .earlyMorning: return "이른 아침"
        case .morning:      return "오전"
        case .afternoon:    return "오후"
        case .evening:      return "저녁"
        case .night:        return "밤"
        case .bedtime:      return "취침"
        }
    }

    static func current() -> TimeSegment {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<7:   return .wakeUp
        case 7..<9:   return .earlyMorning
        case 9..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        case 21..<23: return .night
        default:      return .bedtime
        }
    }
}

enum TimeOfDay: String, Codable {
    case current   = "current"
    case morning   = "morning"
    case afternoon = "afternoon"
    case evening   = "evening"
    case night     = "night"
}

// MARK: - 일일 컨텍스트

struct DailyContext: Codable {
    var dayType: DayType
    var timeSegment: TimeSegment
    var note: String?
    var medicationTaken: Bool
    var locationName: String?

    init(dayType: DayType = .normal,
         timeSegment: TimeSegment = .current(),
         note: String? = nil,
         medicationTaken: Bool = false,
         locationName: String? = nil) {
        self.dayType = dayType
        self.timeSegment = timeSegment
        self.note = note
        self.medicationTaken = medicationTaken
        self.locationName = locationName
    }
}

// MARK: - 데이터 포인트

struct DizzinessDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let gyroscope: GyroscopeData
    let accelerometer: AccelerometerData
    let heartRate: Double
    let heartRateVariability: Double?
    let confidence: Double
    let severity: DizzinessSeverity

    init(
        gyroscope: GyroscopeData,
        accelerometer: AccelerometerData,
        heartRate: Double,
        heartRateVariability: Double? = nil,
        confidence: Double,
        severity: DizzinessSeverity
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.gyroscope = gyroscope
        self.accelerometer = accelerometer
        self.heartRate = heartRate
        self.heartRateVariability = heartRateVariability
        self.confidence = confidence
        self.severity = severity
    }
}

// MARK: - 어지럼증 에피소드

struct DizzinessEpisode: Codable, Identifiable {
    let id: UUID
    var startTime: Date
    var endTime: Date
    var dataPoints: [DizzinessDataPoint]
    var peakSeverity: DizzinessSeverity
    var avgConfidence: Double
    var isManualReport: Bool
    var posture: Posture
    var timeOfDay: TimeOfDay?
    var dailyContext: DailyContext?
    var voiceLevelAtStart: VoiceLevel?
    var triggerEstimate: String

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var durationText: String {
        let seconds = Int(duration)
        if seconds < 60 { return "\(seconds)초" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes)분 \(secs)초"
    }

    init() {
        self.id = UUID()
        self.startTime = Date()
        self.endTime = Date()
        self.dataPoints = []
        self.peakSeverity = .none
        self.avgConfidence = 0
        self.isManualReport = false
        self.posture = .unknown
        self.timeOfDay = nil
        self.dailyContext = nil
        self.voiceLevelAtStart = nil
        self.triggerEstimate = ""
    }
}

// MARK: - 수동 보고

struct ManualDizzinessReport: Codable {
    let severity: DizzinessSeverity
    let context: DailyContext
    var voiceLevelAtTime: VoiceLevel?
    var heartRateAtTime: Double
    let timestamp: Date

    init(severity: DizzinessSeverity,
         context: DailyContext,
         voiceLevelAtTime: VoiceLevel? = nil,
         heartRateAtTime: Double = 0,
         timestamp: Date = Date()) {
        self.severity = severity
        self.context = context
        self.voiceLevelAtTime = voiceLevelAtTime
        self.heartRateAtTime = heartRateAtTime
        self.timestamp = timestamp
    }
}

// MARK: - Watch 통신 키

enum WatchMessageKey: String {
    case dizzinessEpisode = "dizziness_episode"
    case manualReport     = "manual_report"
    case requestSync      = "request_sync"
    case dailyContext     = "daily_context"
    case locationUpdate   = "location_update"
    case voiceAlert       = "voice_alert"
}

// MARK: - HealthKit 일일 데이터

struct HealthKitDailyData: Codable {
    let date: String
    let heartRate: HeartRateData
    let heartRateVariability: HRVData
    let sleep: SleepData
    let activity: ActivityData
    let oxygen: OxygenData?
    let noise: NoiseData?
    let source: String
    let syncedAt: String
}

struct HeartRateData: Codable {
    let current: Double
    let resting: Double
    let max: Double
    let min: Double
    let avg: Double
}

struct HRVData: Codable {
    let avg: Double
    let trend: String
}

struct SleepData: Codable {
    let duration: Double
    let deepSleep: Double
    let remSleep: Double
    let awakenings: Int
    let quality: String
}

struct ActivityData: Codable {
    let steps: Int
    let distance: Double
    let activeEnergy: Double
    let exerciseMinutes: Int
    let level: String
}

struct OxygenData: Codable {
    let spo2: Double
}

struct NoiseData: Codable {
    let avgDecibels: Double
}

// MARK: - API 응답

struct CareFlowAPIResponse: Codable {
    let success: Bool
    let message: String
}

enum CareFlowError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)
    case encodingError
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "유효하지 않은 서버 응답"
        case .serverError(let code): return "서버 오류 (\(code))"
        case .encodingError: return "데이터 인코딩 오류"
        case .networkError(let msg): return "네트워크 오류: \(msg)"
        }
    }
}

struct DizzinessEpisodePayload: Codable {
    let startTime: Date
    let endTime: Date
    let peakSeverity: String
    let avgConfidence: Double
    let isManualReport: Bool
    let posture: String
    let triggerEstimate: String
    let dataPointCount: Int

    init(from episode: DizzinessEpisode) {
        self.startTime = episode.startTime
        self.endTime = episode.endTime
        self.peakSeverity = episode.peakSeverity.rawValue
        self.avgConfidence = episode.avgConfidence
        self.isManualReport = episode.isManualReport
        self.posture = episode.posture.rawValue
        self.triggerEstimate = episode.triggerEstimate
        self.dataPointCount = episode.dataPoints.count
    }
}

// MARK: - 위치 기록

struct LocationRecord: Codable, Identifiable {
    let id: UUID
    let placeName: String
    let latitude: Double
    let longitude: Double
    let visitCount: Int
    let lastVisit: Date

    init(placeName: String, latitude: Double, longitude: Double,
         visitCount: Int = 1, lastVisit: Date = Date()) {
        self.id = UUID()
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.visitCount = visitCount
        self.lastVisit = lastVisit
    }
}
