// ============================================================================
// CareFlow Watch — watchOS App Entry Point (v3.1)
// ============================================================================
// Apple Watch 앱: 센서 + 어지럼증 감지 + 음성 모니터 + 일상 기록
// ============================================================================

import SwiftUI
import HealthKit

@main
struct CareFlowWatch_Watch_App: App {
    @StateObject private var motionManager = MotionSensorManager()
    @StateObject private var dizzinessDetector = WatchDizzinessDetector()
    @StateObject private var voiceMonitor = VoiceDecibelMonitor()
    @StateObject private var contextManager = DailyContextManager()

    init() {
        // 모든 매니저 간 참조 연결은 onAppear에서 처리
    }

    var body: some Scene {
        WindowGroup {
            WatchMainView()
                .environmentObject(motionManager)
                .environmentObject(dizzinessDetector)
                .environmentObject(voiceMonitor)
                .environmentObject(contextManager)
                .onAppear {
                    setupInterModuleConnections()
                }
        }
    }

    // MARK: - v3.1: 모듈 간 상호관련성 연결 (핵심!)

    private func setupInterModuleConnections() {
        // ─── 1. Detector ← ContextManager, VoiceMonitor 주입 ───
        dizzinessDetector.contextManager = contextManager
        dizzinessDetector.voiceMonitor = voiceMonitor

        // ─── 2. MotionSensor → Detector 실시간 파이프라인 (P1 핵심 수정) ───
        // 이전: onNewDataPoint 미설정 → Detector가 센서 데이터를 받지 못함
        // 수정: gyro + accel + 실시간 HR을 Detector.processNewData로 전달
        motionManager.onNewDataPoint = { [weak dizzinessDetector, weak motionManager] gyro, accel, heartRate in
            // HR이 0이면 detector의 latestHeartRate 사용 (HealthKit에서 수신한 값)
            let effectiveHR = heartRate > 0 ? heartRate : (dizzinessDetector?.latestHeartRate ?? 0)
            dizzinessDetector?.processNewData(gyro: gyro, accel: accel, heartRate: effectiveHR)
        }

        // ─── 3. 센서 모니터링 자동 시작 ───
        motionManager.startMonitoring(frequency: .normal)

        // ─── 4. 음성 모니터링 자동 시작 ───
        voiceMonitor.startMonitoring()

        // ─── 5. watchOS HealthKit 실시간 심박수 관찰 ───
        startWatchHeartRateObserver()

        // ─── 6. 맥락 데이터 로드 ───
        contextManager.loadOnAppear()

        print("✅ v3.1: 모듈 간 상호연결 완료 (Sensor→Detector→Context→Voice→HR)")
    }

    // MARK: - watchOS 실시간 심박수 (HKAnchoredObjectQuery)

    private func startWatchHeartRateObserver() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let healthStore = HKHealthStore()
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        // 읽기 권한 요청
        healthStore.requestAuthorization(toShare: nil, read: [hrType]) { success, _ in
            guard success else { return }

            // Anchored Query: 새 심박 데이터가 생길 때마다 콜백
            let query = HKAnchoredObjectQuery(
                type: hrType,
                predicate: nil,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, _ in
                self.processHeartRateSamples(samples)
            }

            // 업데이트 핸들러 — 새 데이터 도착 시 실시간 호출
            query.updateHandler = { _, samples, _, _, _ in
                self.processHeartRateSamples(samples)
            }

            healthStore.execute(query)
            print("🫀 watchOS 실시간 심박 관찰 시작")
        }
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let hrSamples = samples as? [HKQuantitySample],
              let latest = hrSamples.last else { return }

        let hr = latest.quantity.doubleValue(for: HKUnit(from: "count/min"))

        // Detector에 실시간 HR 전달
        dizzinessDetector.updateLiveHeartRate(hr)

        // MotionSensorManager에도 반영 (UI 표시용)
        motionManager.updateHeartRate(hr)

        print("🫀 실시간 HR: \(String(format: "%.0f", hr)) bpm → Detector")
    }
}
