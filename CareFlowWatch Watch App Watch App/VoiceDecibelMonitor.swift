// ============================================================================
// CareFlow Watch — Voice Decibel Monitor (watchOS)
// ============================================================================
// 사용자 음성 크기 모니터링 + 자기 조절 유도
//
// 핵심 원리:
//   이명 환자는 본인 목소리가 잘 들리지 않아 무의식적으로 큰 소리로 말함
//   → 평상시 데시벨 기저선 학습 후 과도하게 커지면 진동/햅틱으로 알림
//   → 사용자가 스스로 목소리 크기를 자각하고 조절할 수 있도록 유도
//
// 기술 구현:
//   AVAudioEngine 사용 (watchOS 9+)
//   - installTap: 마이크 입력을 실시간 분석
//   - RMS → dB 변환: 20 * log10(rms)
//   - 기저선: 첫 5분간 평균 dB 자동 학습
//
// 데시벨 기준:
//   🔇 < 60 dB   — 조용 (속삭임~정상 대화)
//   🔈 60~70 dB  — 보통 대화
//   🔉 70~80 dB  — 다소 큰 목소리
//   🔊 80+ dB    — 매우 큼 → 진동 알림
//
// 개인정보 보호:
//   - 음성 내용은 녹음/저장하지 않음
//   - 데시벨(크기)만 수치로 측정
//   - 사용자가 언제든 끌 수 있음
// ============================================================================

import Foundation
import AVFoundation
import Combine
#if os(watchOS)
import WatchKit
#endif

class VoiceDecibelMonitor: ObservableObject {

    // MARK: - Published

    @Published var isMonitoring = false
    @Published var currentDecibel: Double = 0.0
    @Published var currentVoiceLevel: VoiceLevel = .quiet
    @Published var baselineDecibel: Double = 65.0    // 학습 전 기본값
    @Published var isCalibrating = false             // 기저선 학습 중
    @Published var showVoiceAlert = false
    @Published var voiceAlertHistory: [VoiceAlertRecord] = []

    // MARK: - Settings

    /// 기저선 대비 이 값 이상 높으면 알림 (dB)
    var alertThreshold: Double = 12.0

    /// 큰 소리가 이 시간(초) 이상 지속되면 알림
    var sustainedDuration: TimeInterval = 3.0

    /// 진동 피드백 활성화
    var hapticEnabled: Bool = true

    // MARK: - Private

    private var audioEngine: AVAudioEngine?
    private var calibrationSamples: [Double] = []
    private let calibrationCount = 30  // 30샘플 (약 5분 @ 10초 간격)
    private var loudStartTime: Date?
    private var feedbackCooldown = false

    // MARK: - 시작/중지

    func startMonitoring() {
        guard !isMonitoring else { return }

        #if targetEnvironment(simulator)
        // 시뮬레이터는 마이크 없음 — 더미 모드로 실행
        DispatchQueue.main.async {
            self.isMonitoring = true
            self.currentDecibel = 65.0
            self.currentVoiceLevel = .normal
        }
        print("🎤 시뮬레이터 모드: 더미 음성 모니터링")
        return
        #endif

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // 유효하지 않은 포맷 방어
        guard format.sampleRate > 0 else {
            print("🎤 오디오 입력 포맷 없음 — 모니터링 건너뜀")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try audioEngine.start()
            self.audioEngine = audioEngine

            DispatchQueue.main.async {
                self.isMonitoring = true
                self.isCalibrating = self.calibrationSamples.count < self.calibrationCount
            }

            print("🎤 음성 데시벨 모니터링 시작 (기저선: \(baselineDecibel) dB)")
        } catch {
            print("🎤 오디오 엔진 시작 실패: \(error)")
        }
    }

    func stopMonitoring() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        DispatchQueue.main.async {
            self.isMonitoring = false
            self.isCalibrating = false
            self.currentDecibel = 0
            self.currentVoiceLevel = .quiet
        }

        print("🎤 음성 데시벨 모니터링 중지")
    }

    // MARK: - 오디오 버퍼 처리

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // RMS 계산
        var sum: Float = 0
        for i in 0..<frameCount {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameCount))

        // RMS → dB 변환
        let db: Double
        if rms > 0 {
            db = max(0, Double(20 * log10(rms)) + 100)  // +100 offset (0~120 범위로)
        } else {
            db = 0
        }

        // 기저선 학습
        if calibrationSamples.count < calibrationCount {
            calibrationSamples.append(db)
            if calibrationSamples.count == calibrationCount {
                let avg = calibrationSamples.reduce(0, +) / Double(calibrationSamples.count)
                DispatchQueue.main.async {
                    self.baselineDecibel = avg
                    self.isCalibrating = false
                }
                print("🎤 기저선 학습 완료: \(String(format: "%.1f", avg)) dB")
            }
        }

        // 음성 레벨 판정
        let level = classifyVoiceLevel(db)

        DispatchQueue.main.async {
            self.currentDecibel = db
            self.currentVoiceLevel = level
        }

        // 알림 판정
        checkAndAlert(db: db, level: level)
    }

    // MARK: - 레벨 분류

    private func classifyVoiceLevel(_ db: Double) -> VoiceLevel {
        if db < 60       { return .quiet }
        if db < 70       { return .normal }
        if db < 80       { return .loud }
        return .veryLoud
    }

    // MARK: - 알림 + 햅틱 피드백

    private func checkAndAlert(db: Double, level: VoiceLevel) {
        let overThreshold = db > baselineDecibel + alertThreshold

        if overThreshold {
            if loudStartTime == nil {
                loudStartTime = Date()
            }

            // 지속 시간 체크
            if let start = loudStartTime,
               Date().timeIntervalSince(start) >= sustainedDuration,
               !feedbackCooldown {
                triggerVoiceFeedback(db: db, level: level)
            }
        } else {
            // 정상으로 돌아옴
            if loudStartTime != nil {
                loudStartTime = nil
                feedbackCooldown = false
            }
        }
    }

    private func triggerVoiceFeedback(db: Double, level: VoiceLevel) {
        feedbackCooldown = true

        // 햅틱 피드백 (워치 진동)
        #if os(watchOS)
        if hapticEnabled {
            WKInterfaceDevice.current().play(.notification)
        }
        #endif

        // 기록 저장
        let record = VoiceAlertRecord(
            peakDecibel: db,
            duration: sustainedDuration,
            voiceLevel: level
        )

        DispatchQueue.main.async {
            self.showVoiceAlert = true
            self.voiceAlertHistory.append(record)
            if self.voiceAlertHistory.count > 100 {
                self.voiceAlertHistory.removeFirst()
            }
        }

        print("🔊 음성 알림! \(String(format: "%.0f", db)) dB (기저선 대비 +\(String(format: "%.0f", db - baselineDecibel)) dB)")

        // 5초 후 쿨다운 해제
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.feedbackCooldown = false
            self?.showVoiceAlert = false
        }
    }

    // MARK: - 기저선 리셋

    /// 기저선을 다시 학습 (환경이 바뀌었을 때)
    func recalibrate() {
        calibrationSamples = []
        DispatchQueue.main.async {
            self.isCalibrating = true
        }
        print("🎤 기저선 재학습 시작")
    }

    // MARK: - 통계

    /// 오늘 음성 알림 횟수
    var todayAlertCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return voiceAlertHistory.filter { $0.timestamp >= today }.count
    }

    /// 평균 피크 데시벨
    var avgPeakDecibel: Double {
        guard !voiceAlertHistory.isEmpty else { return 0 }
        return voiceAlertHistory.reduce(0) { $0 + $1.peakDecibel } / Double(voiceAlertHistory.count)
    }
}
