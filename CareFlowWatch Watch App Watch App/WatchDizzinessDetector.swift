// ============================================================================
// CareFlow Watch — Dizziness Detector (watchOS)
// ============================================================================
// 실시간 어지럼증 감지 엔진 (Apple Watch에서 직접 실행)
//
// 감지 원리 (v2.0 — Evidence-Based):
//   1차 지표: 심박 변화 (교감신경 활성화 = 발작 조기 경보)    [5][6]
//   2차 지표: 자이로 회전 각속도 (균형 이탈 감지)              [1]
//   3차 지표: 가속도계 기울기 (자세 변화 감지)                 [4]
//   4차: 패턴 지속 시간 확인 (10초+ 짧은 / 5분+ 연장)
//
// 근거 출처:
//   [1] ADL wrist gyro 4.21 rad/s — Threshold Analysis of Wrist-Worn Sensors
//   [4] Normal gait tilt 5~15° — BMC Geriatrics falls prediction
//   [5] HR elevation before Ménière's attack — Frontiers in Neurology, 2022
//   [6] HRV parasympathetic suppression pre-attack — PubMed 10530737
//   [11] Ménière's episode minimum 20min — Mayo Clinic
//
// 질병분류: ICD-10: R42 | KCD: R42
// ============================================================================

import Foundation
import WatchConnectivity
import Combine

class WatchDizzinessDetector: ObservableObject {

    // MARK: - Published

    @Published var isDetecting = false
    @Published var currentConfidence: Double = 0
    @Published var currentSeverity: DizzinessSeverity = .none  // 🟢 정상 상태로 시작
    @Published var alertMessage: String = ""
    @Published var showAlert = false
    @Published var currentEpisode: DizzinessEpisode?
    @Published var episodeHistory: [DizzinessEpisode] = []

    // MARK: - Evidence-Based Thresholds (v2.0)

    /// 임계값 구조체 — 모든 값에 문헌 근거 또는 "가정" 표기
    struct Thresholds {
        // ── 자이로스코프 ──
        // [1] ADL wrist angular velocity = 241 deg/s = 4.21 rad/s
        // 4.5 rad/s = ADL 상단 + 안전 여유
        var gyroVelocity: Double = 4.5         // rad/s (이전: 2.0)

        // ── 기울기 ──
        // [4] 정상 보행 골반 기울기 5~15°
        // 22° = 정상 상단(15°) + 7° 여유
        var tiltChange: Double = 22.0           // degrees (이전: 15.0)

        // ── 심박수 변화 ──
        // [5] 메니에르 발작 직전 HR "유의하게 상승" — 교감신경 활성화
        // 10 bpm = 조기 감지 민감도 향상 (이전 15 bpm에서 감소)
        var heartRateChange: Double = 10.0      // bpm (이전: 15.0)

        // ── 에피소드 최소 지속 시간 ──
        // 노이즈 필터 + 짧은 기립성 사건 포착
        var minDuration: TimeInterval = 10.0    // seconds (이전: 5.0)

        // ── 알림 기준 ──
        // 가정: confidence 60% 이상에서 알림 (HR 민감도 향상에 맞춤)
        var alertThreshold: Double = 60.0       // confidence % (이전: 70.0)

        // ── 메니에르 연장 에피소드 기준 ──
        // [11] Mayo Clinic: 메니에르 발작 최소 20분
        // 5분 = 조기 판별 기준 (20분 기다리면 너무 늦음)
        var extendedEpisodeThreshold: TimeInterval = 300.0  // 5분 (신규)
    }

    var thresholds = Thresholds()

    // ── 기저 심박수 ──
    // [5][6] 개인화 필수: 약물 복용 시 기저 심박 변경됨
    // HealthKit restingHeartRate에서 자동 갱신, 72는 fallback 값
    var baselineHeartRate: Double = 72.0 {
        didSet {
            print("🫀 기저 심박수 갱신: \(oldValue) → \(baselineHeartRate) bpm")
        }
    }

    /// HealthKit에서 안정 심박수를 받아서 개인화
    func updateBaselineFromHealthKit(restingHR: Double) {
        if restingHR > 40 && restingHR < 120 {  // 합리적 범위 체크
            baselineHeartRate = restingHR
        }
    }

    // MARK: - Daily Context & Manual Report (v3.0)

    @Published var manualReports: [ManualDizzinessReport] = []

    /// DailyContextManager 참조 — App Entry Point에서 주입
    weak var contextManager: DailyContextManager?

    /// VoiceDecibelMonitor 참조 — App Entry Point에서 주입
    weak var voiceMonitor: VoiceDecibelMonitor?

    /// LocationTracker 참조 — iOS App Entry Point에서 주입 (v3.1)
    /// watchOS에서는 nil (위치 추적은 iPhone 측에서 처리)
   

    // MARK: - 실시간 심박수 (v3.1)ㄴ

    /// 가장 최근 수신된 실시간 HR — processNewData에 자동 반영
    @Published var latestHeartRate: Double = 0

    /// 외부에서 실시간 HR 업데이트 (HealthKit workout / HKAnchoredObjectQuery)
    func updateLiveHeartRate(_ hr: Double) {
        guard hr > 30 && hr < 250 else { return }  // 유효 범위 체크
        DispatchQueue.main.async {
            self.latestHeartRate = hr
        }
    }

    /// 사용자가 워치 버튼으로 "지금 어지러워요" 보고
    func reportDizzinessManually(severity: DizzinessSeverity = .moderate) {
        let context = contextManager?.captureContext(note: "수동 보고") ?? DailyContext()

        var report = ManualDizzinessReport(severity: severity, context: context)
        report.voiceLevelAtTime = voiceMonitor?.currentVoiceLevel
        report.heartRateAtTime = baselineHeartRate  // 현재 가용한 HR

        DispatchQueue.main.async {
            self.manualReports.insert(report, at: 0)
            if self.manualReports.count > 50 {
                self.manualReports.removeLast()
            }
        }

        // 수동 보고를 에피소드로도 기록
        var episode = DizzinessEpisode()
        episode.peakSeverity = severity
        episode.isManualReport = true
        episode.dailyContext = context
        episode.voiceLevelAtStart = voiceMonitor?.currentVoiceLevel
        episode.triggerEstimate = "사용자 직접 보고 (\(context.timeSegment.label), \(context.dayType.label))"

        DispatchQueue.main.async {
            self.episodeHistory.insert(episode, at: 0)
            if self.episodeHistory.count > 50 {
                self.episodeHistory.removeLast()
            }
        }

        // iPhone 전송
        sendEpisodeToiPhone(episode)

        print("🆘 수동 보고: \(severity.emoji) \(severity.label) — \(context.dayType.emoji) \(context.timeSegment.emoji)")
    }

    // MARK: - Private

    private var dataBuffer: [DizzinessDataPoint] = []
    private let maxBufferSize = 300  // 30초 (10Hz)
    private var episodeStartTime: Date?
    private var consecutiveAnomalies = 0

    // MARK: - 센서 데이터 처리

    /// MotionSensorManager에서 새 데이터가 올 때마다 호출
    func processNewData(gyro: GyroscopeData, accel: AccelerometerData, heartRate: Double = 0) {
        // 0. 유효 심박수 결정 — HR 0은 "미수집" 의미, baseline으로 대체
        let effectiveHR = heartRate > 0 ? heartRate : baselineHeartRate

        // 1. 신뢰도 계산
        let confidence = calculateConfidence(gyro: gyro, accel: accel, heartRate: effectiveHR)
        let severity = getSeverity(confidence: confidence)

        // 2. 데이터 포인트 생성
        let point = DizzinessDataPoint(
            gyroscope: gyro,
            accelerometer: accel,
            heartRate: effectiveHR,
            confidence: confidence,
            severity: severity
        )

        // 3. 버퍼에 추가
        dataBuffer.append(point)
        if dataBuffer.count > maxBufferSize {
            dataBuffer.removeFirst()
        }

        // 4. UI 업데이트
        DispatchQueue.main.async {
            self.currentConfidence = confidence
            self.currentSeverity = severity
        }

        // 5. 이상 감지 — 다중 신호 기반 (v2.0)
        // 조건 A: 기존 — 자이로 또는 기울기 임계 초과 (급성 움직임)
        // 조건 B: 신규 — 심박만 올랐는데 움직임 없음 (메니에르 패턴) [5]
        let motionAnomalous = gyro.magnitude > thresholds.gyroVelocity ||
                              accel.tilt > thresholds.tiltChange
        let hrDiffAnomaly = abs(effectiveHR - baselineHeartRate)
        let menierePattern = hrDiffAnomaly >= thresholds.heartRateChange && gyro.magnitude < 1.0
        let isAnomalous = motionAnomalous || menierePattern

        if isAnomalous {
            consecutiveAnomalies += 1

            // 에피소드 시작
            if consecutiveAnomalies == 3 && currentEpisode == nil {
                startEpisode()
            }

            // 에피소드 진행 중이면 데이터 추가
            if var episode = currentEpisode {
                episode.dataPoints.append(point)
                episode.endTime = Date()

                if severity.rawValue > episode.peakSeverity.rawValue {
                    episode.peakSeverity = severity
                }

                DispatchQueue.main.async {
                    self.currentEpisode = episode
                }
            }

            // 알림 발송
            if confidence >= thresholds.alertThreshold {
                triggerAlert(severity: severity, confidence: confidence)
            }

        } else {
            // 정상 데이터
            if consecutiveAnomalies > 0 {
                consecutiveAnomalies -= 1
            }

            // 에피소드 종료 판정 (3초 연속 정상)
            if consecutiveAnomalies == 0 && currentEpisode != nil {
                endEpisode()
            }
        }
    }

    // MARK: - 에피소드 관리

    private func startEpisode() {
        var episode = DizzinessEpisode()
        episode.posture = estimatePosture()
        episode.timeOfDay = .current
        // v3.0: 에피소드 시작 시 일상 맥락 캡처
        episode.dailyContext = contextManager?.captureContext()
        episode.voiceLevelAtStart = voiceMonitor?.currentVoiceLevel

        DispatchQueue.main.async {
            self.currentEpisode = episode
            self.isDetecting = true
        }

        print("🔴 어지럼증 에피소드 시작 — \(episode.dailyContext?.dayType.emoji ?? "?") \(episode.dailyContext?.timeSegment.emoji ?? "?")")
    }

    private func endEpisode() {
        guard var episode = currentEpisode else { return }

        episode.endTime = Date()
        episode.avgConfidence = episode.dataPoints.isEmpty ? 0.0 :
            episode.dataPoints.reduce(0.0) { $0 + $1.confidence } / Double(episode.dataPoints.count)
        episode.triggerEstimate = estimateTrigger(episode: episode)

        // 최소 지속 시간 확인 (v2.0: 10초 이상)
        if episode.duration >= thresholds.minDuration {

            // ── 에피소드 이중 분류 (v2.0) ──
            // [11] Mayo Clinic: 메니에르 발작 최소 20분
            // ShortEvent (10초~5분): 기립성 어지러움, 일시적 균형 변화
            // ExtendedEpisode (5분+): 메니에르 발작 가능성 → 의료 연결 고려
            let episodeType: String
            if episode.duration >= thresholds.extendedEpisodeThreshold {
                episodeType = "🔴 ExtendedEpisode"
                // 연장 에피소드 → 심각도 강제 승격
                if episode.peakSeverity != .severe {
                    episode.peakSeverity = .severe
                }
            } else {
                episodeType = "🟠 ShortEvent"
            }

            DispatchQueue.main.async {
                self.episodeHistory.insert(episode, at: 0)
                if self.episodeHistory.count > 50 {
                    self.episodeHistory.removeLast()
                }
            }


            print("✅ \(episodeType) 종료 (지속: \(episode.durationText), 심각도: \(episode.peakSeverity.label))")
        } else {
            print("⏭ 에피소드 무시 (지속 \(Int(episode.duration))초 < 최소 \(Int(thresholds.minDuration))초)")
        }

        DispatchQueue.main.async {
            self.currentEpisode = nil
            self.isDetecting = false
            self.consecutiveAnomalies = 0
        }
    }

    // MARK: - 신뢰도 계산 (v2.0 Evidence-Based)

    /// confidence 계산 — v3.1 가중치 재조정 (음성 데시벨 통합)
    ///
    /// HR 35%  [5] 발작 직전 심박 상승이 1차 지표 (교감신경 활성화)
    /// Gyro 25% [1] ADL 4.21 rad/s 기반 — 초과 시 의미있는 이상
    /// Tilt 15% [4] 손목 기울기는 자세의 간접 지표 — 가중치 하향
    /// 움직임감소 보너스 10% — 메니에르 발작 시 환자가 멈추는 패턴
    /// 음성 보너스 5% — 이명 환자 무의식적 큰 목소리 = 전정기능 보상 행동
    /// 맥락 보너스 10% — 고위험 시간대(기상직후, 취침전) + 약 미복용
    private func calculateConfidence(gyro: GyroscopeData, accel: AccelerometerData, heartRate: Double) -> Double {

        // ── 심박 기여도 (35%) — 1차 지표 ──
        let hrDiff = abs(heartRate - baselineHeartRate)
        let hrScore = min(1.0, hrDiff / (thresholds.heartRateChange * 2)) * 35

        // ── 자이로 기여도 (25%) — 2차 지표 ──
        let gyroScore = min(1.0, gyro.magnitude / (thresholds.gyroVelocity * 2)) * 25

        // ── 기울기 기여도 (15%) — 3차 지표 ──
        let tiltScore = min(1.0, accel.tilt / (thresholds.tiltChange * 2)) * 15

        // ── 움직임 감소 보너스 (10%) — 메니에르 특화 ──
        let motionStillnessBonus: Double
        if hrDiff >= thresholds.heartRateChange && gyro.magnitude < 1.0 {
            motionStillnessBonus = 10.0
        } else {
            motionStillnessBonus = 0.0
        }

        // ── 음성 데시벨 보너스 (5%) — v3.1 신규 ──
        // 이명 환자가 큰 소리로 말하는 것은 전정기능 보상 행동의 일환
        // 큰 목소리 + 다른 신호 = 복합 이상 가능성 증가
        let voiceBonus: Double
        if let monitor = voiceMonitor {
            switch monitor.currentVoiceLevel {
            case .veryLoud: voiceBonus = 5.0   // 80+ dB — 명확한 이상 신호
            case .loud:     voiceBonus = 3.0   // 70-80 dB — 경미한 보정
            default:        voiceBonus = 0.0
            }
        } else {
            voiceBonus = 0.0
        }

        // ── 맥락 보너스 (10%) — v3.1 신규 ──
        // 기상직후/취침전 = 기립성 어지러움 호발 시간대 → 민감도 상향
        // 약 미복용 = 증상 발현 위험 증가
        let contextBonus: Double
        if let ctx = contextManager {
            var bonus = 0.0
            let segment = ctx.currentTimeSegment
            if segment == .wakeUp || segment == .bedtime {
                bonus += 5.0  // 고위험 시간대
            }
            if !ctx.medicationTaken {
                bonus += 5.0  // 약 미복용
            }
            contextBonus = bonus
        } else {
            contextBonus = 0.0
        }

        return min(100, hrScore + gyroScore + tiltScore + motionStillnessBonus + voiceBonus + contextBonus)
    }

    /// 🚦 신뢰도 → NANDA 4유형 매핑
    /// 임계값 20/50/80은 직접적 임상 근거 없음 — 실측 데이터 확보 후 보정 필요
    /// Phase 2에서 환자 S데이터(주관 호소)와 confidence를 대조하여 재설정 예정
    ///
    /// 🟢 <20  — Readiness for enhanced (정상, 향상 가능)
    /// 🟡 20~49 — Risk for (위험 가능성, 주의)
    /// 🟠 50~79 — Actual ~~ Related To (현상 발생 중)
    /// 🔴 ≥80  — PC: Potential Complication (즉각 대응)
    private func getSeverity(confidence: Double) -> DizzinessSeverity {
        if confidence >= 80 { return .severe   } // 🔴 PC — 보정 대기
        if confidence >= 50 { return .moderate } // 🟠 Actual — 보정 대기
        if confidence >= 20 { return .mild     } // 🟡 Risk — 보정 대기
        return .none                              // 🟢 Readiness
    }

    // MARK: - 트리거 추정

    private func estimateTrigger(episode: DizzinessEpisode) -> String {
        let avgTilt = episode.dataPoints.isEmpty ? 0.0 :
            episode.dataPoints.reduce(0.0) { $0 + $1.accelerometer.tilt } / Double(episode.dataPoints.count)

        // v4.1: 진단명 없이 "관찰된 현상 패턴" 표현
        if avgTilt > 30 { return "갑작스러운 자세 변화 패턴 감지" }

        let hour = Calendar.current.component(.hour, from: episode.startTime)
        if hour >= 0 && hour < 7 { return "수면 후 기립 시 균형 변화 패턴" }
        if hour >= 7 && hour < 9 { return "기상 직후 자세 변화와 관련된 균형 변화" }

        let avgGyro = episode.dataPoints.isEmpty ? 0.0 :
            episode.dataPoints.reduce(0.0) { $0 + $1.gyroscope.magnitude } / Double(episode.dataPoints.count)
        if avgGyro > 3.0 { return "강한 회전 운동과 관련된 균형감각 변화" }

        return "패턴 분석 중 (추가 관찰 필요)"
    }

    // MARK: - 자세 추정

    private func estimatePosture() -> Posture {
        guard let last = dataBuffer.last else { return .unknown }
        let tilt = last.accelerometer.tilt
        let accelMag = last.accelerometer.magnitude

        if tilt > 60 { return .lying }
        if accelMag < 1.05 { return .sitting }
        if accelMag < 1.3 { return .standing }
        return .walking
    }

    // MARK: - 알림

    /// 🚦 NANDA 유형별 알림 메시지 — v4.1 현상 언어 사용
    private func triggerAlert(severity: DizzinessSeverity, confidence: Double) {
        let message: String
        switch severity {
        case .none:
            return  // 🟢 정상 — 알림 불필요
        case .mild:
            message = "🟡 균형감각 변화 가능성이 감지됩니다.\nRisk for falls — 천천히 움직이세요."
        case .moderate:
            message = "🟠 전정기능과 관련된 균형 변화가 관찰됩니다.\n갑자기 움직이지 말고 천천히요."
        case .severe:
            message = "🔴 즉각적 대응이 필요한 현상이 감지됐습니다.\nPC: 안전한 곳에서 즉시 앉거나 누우세요."
        }

        DispatchQueue.main.async {
            self.alertMessage = message
            self.showAlert = true
        }
    }

    // MARK: - iPhone 통신

    private func sendEpisodeToiPhone(_ episode: DizzinessEpisode) {
        guard WCSession.default.isReachable else {
            // iPhone 연결 안 될 때 → transferUserInfo (백그라운드 전송)
            sendEpisodeBackground(episode)
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(episode)

            WCSession.default.sendMessage(
                [WatchMessageKey.dizzinessEpisode.rawValue: data],
                replyHandler: { reply in
                    print("iPhone 전송 완료: \(reply)")
                },
                errorHandler: { error in
                    print("iPhone 전송 실패: \(error)")
                    self.sendEpisodeBackground(episode)
                }
            )
        } catch {
            print("에피소드 인코딩 실패: \(error)")
        }
    }

    private func sendEpisodeBackground(_ episode: DizzinessEpisode) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(episode)

            WCSession.default.transferUserInfo([
                WatchMessageKey.dizzinessEpisode.rawValue: data
            ])
            print("백그라운드 전송 예약됨")
        } catch {
            print("백그라운드 전송 실패: \(error)")
        }
    }
}
