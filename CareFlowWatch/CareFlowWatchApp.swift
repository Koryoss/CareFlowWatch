// ============================================================================
// CareFlow Watch — iOS App Entry Point (v3.1)
// ============================================================================
// iPhone 앱: HealthKit + Watch 브릿지 + 일상 기록 + 위치 추적
// ============================================================================

import SwiftUI
import Combine

@main
struct CareFlowWatchApp: App {
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var connectivityManager = WatchConnectivityManager()
    @StateObject private var contextManager = DailyContextManager()
    // TODO: LocationTracker 추가 필요 (위 방법 참고)
    // @StateObject private var locationTracker = LocationTracker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
                .environmentObject(connectivityManager)
                .environmentObject(contextManager)
                // .environmentObject(locationTracker)
                .onAppear {
                    setupInterModuleConnections()
                }
        }
    }

    // MARK: - v3.1: iOS 측 모듈 간 상호관련성 연결

    private func setupInterModuleConnections() {

        // ─── 1. WatchConnectivity ← ContextManager, LocationTracker 주입 ───
        connectivityManager.contextManager = contextManager
        // connectivityManager.locationTracker = locationTracker  // TODO: LocationTracker 활성화 후 주석 해제

        // ─── 2. HealthKit → WatchConnectivity → Watch Detector (기저 심박수 파이프라인) ───
        // HealthKit에서 안정 심박수가 갱신되면 → Watch Detector로 자동 전달
        healthKitManager.onRestingHRUpdated = { [weak connectivityManager] restingHR in
            connectivityManager?.sendBaselineHRToWatch(restingHR)
            print("🫀 기저 HR \(restingHR) bpm → Watch Detector 전달 완료")
        }

        // Watch가 기저 HR을 요청하면 → HealthKit 최신값 반환
        connectivityManager.onBaselineHRNeeded = { [weak healthKitManager] in
            return healthKitManager?.latestRestingHR ?? 72.0
        }

        // ─── 3. HealthKit 일일 데이터 → 서버 자동 동기화 ───
        healthKitManager.onDailyDataReady = { [weak connectivityManager] dailyData in
            connectivityManager?.syncHealthKitDataToServer(dailyData)
            print("📊 HealthKit 일일 데이터 → 서버 동기화 완료")
        }

        // ─── 4. LocationTracker → DailyContext 장소 이름 자동 반영 ───
        // TODO: LocationTracker 활성화 후 주석 해제
        /*
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak contextManager, weak locationTracker, weak connectivityManager] _ in
            guard let ctx = contextManager, let loc = locationTracker else { return }
            if let placeName = loc.currentPlaceForContext {
                ctx.updateLocationName(placeName)
                connectivityManager?.sendLocationToWatch(placeName)
            }
        }
        */

        // ─── 5. HealthKit 권한 요청 + 데이터 로드 ───
        healthKitManager.requestAuthorization()

        // ─── 6. 위치 추적 시작 ───
        // TODO: LocationTracker 활성화 후 주석 해제
        // locationTracker.requestAuthorization()

        // ─── 7. 맥락 데이터 로드 ───
        contextManager.loadOnAppear()

        print("✅ v3.1: iOS 모듈 간 상호연결 완료 (HealthKit→Watch→Detector→Context→Server) [Location 비활성화]")
    }
}
