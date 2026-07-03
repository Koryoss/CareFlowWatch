import SwiftUI
import HealthKit

@main
struct CareFlowWatch_Watch_App_Watch_AppApp: App {
    @StateObject private var motionManager = MotionSensorManager()
    @StateObject private var dizzinessDetector = WatchDizzinessDetector()
    @StateObject private var voiceMonitor = VoiceDecibelMonitor()
    @StateObject private var contextManager = DailyContextManager()

    var body: some Scene {
        WindowGroup {
            WatchMainView()
                .environmentObject(motionManager)
                .environmentObject(dizzinessDetector)
                .environmentObject(voiceMonitor)
                .environmentObject(contextManager)
                .onAppear {
                    setupConnections()
                }
        }
    }

    private func setupConnections() {
        dizzinessDetector.contextManager = contextManager
        dizzinessDetector.voiceMonitor = voiceMonitor

        #if targetEnvironment(simulator)
        // 시뮬레이터: CoreMotion/Audio/HealthKit 사용 불가 → 더미 모드
        print("🖥️ 시뮬레이터 모드 — 센서 모니터링 비활성화")
        contextManager.loadOnAppear()
        #else
        // 실제 기기에서만 모니터링 시작
        motionManager.onNewDataPoint = { [weak dizzinessDetector, weak motionManager] gyro, accel, heartRate in
            let effectiveHR = heartRate > 0 ? heartRate : (dizzinessDetector?.latestHeartRate ?? 0)
            dizzinessDetector?.processNewData(gyro: gyro, accel: accel, heartRate: effectiveHR)
        }

        motionManager.startMonitoring(frequency: .normal)
        voiceMonitor.startMonitoring()
        startHeartRateObserver()
        contextManager.loadOnAppear()
        #endif
    }

    private func startHeartRateObserver() {
        #if !targetEnvironment(simulator)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let healthStore = HKHealthStore()
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        healthStore.requestAuthorization(toShare: nil, read: Set([hrType])) { success, _ in
            guard success else { return }
            let query = HKAnchoredObjectQuery(
                type: hrType, predicate: nil, anchor: nil, limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, _ in
                self.processHRSamples(samples)
            }
            query.updateHandler = { _, samples, _, _, _ in
                self.processHRSamples(samples)
            }
            healthStore.execute(query)
        }
        #endif
    }

    private func processHRSamples(_ samples: [HKSample]?) {
        guard let hrSamples = samples as? [HKQuantitySample],
              let latest = hrSamples.last else { return }
        let hr = latest.quantity.doubleValue(for: HKUnit(from: "count/min"))
        dizzinessDetector.updateLiveHeartRate(hr)
        motionManager.updateHeartRate(hr)
    }
}
