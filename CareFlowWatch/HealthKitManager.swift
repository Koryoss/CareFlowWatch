// ============================================================================
// CareFlow Watch — HealthKit Manager (iOS)
// ============================================================================
// iPhone에서 HealthKit 데이터를 읽고 CareFlow 서버로 전송
//
// 수집 항목:
//   - 심박수 (Heart Rate)
//   - 심박 변동성 (HRV)
//   - 수면 분석 (Sleep Analysis)
//   - 걸음 수 (Steps)
//   - 활동 에너지 (Active Energy)
//   - 운동 시간 (Exercise Minutes)
//   - 혈중 산소 (SpO2) — optional
//   - 환경 소음 (Noise) — optional
// ============================================================================

import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isAuthorized = false
    @Published var todayData: HealthKitDailyData?
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var latestRestingHR: Double = 72.0   // v3.1: 최신 안정 심박수

    /// v3.1: 기저 심박수 변경 시 외부에 알림 (Detector/WatchConnectivity 연동용)
    var onRestingHRUpdated: ((Double) -> Void)?

    /// v3.1: 일일 데이터 fetch 완료 시 외부 동기화 콜백
    var onDailyDataReady: ((HealthKitDailyData) -> Void)?

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - 권한 요청

    /// HealthKit 데이터 접근 권한 요청
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "이 기기에서 건강 데이터를 사용할 수 없습니다."
            return
        }

        let readTypes: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKQuantityType.quantityType(forIdentifier: .environmentalAudioExposure)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]

        healthStore.requestAuthorization(toShare: nil, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if let error = error {
                    self?.lastError = error.localizedDescription
                }
                if success {
                    Task { await self?.fetchTodayData() }
                }
            }
        }
    }

    // MARK: - 오늘 데이터 가져오기

    @MainActor
    func fetchTodayData() async {
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay)!

        async let heartRate = fetchHeartRateData(from: startOfDay, to: now)
        async let restingHR = fetchRestingHeartRate(from: startOfDay, to: now)
        async let hrv = fetchHRV(from: startOfDay, to: now)
        async let steps = fetchSteps(from: startOfDay, to: now)
        async let energy = fetchActiveEnergy(from: startOfDay, to: now)
        async let exercise = fetchExerciseMinutes(from: startOfDay, to: now)
        async let distance = fetchDistance(from: startOfDay, to: now)
        async let sleep = fetchSleep(from: yesterday, to: now)
        async let spo2 = fetchSpO2(from: startOfDay, to: now)
        async let noise = fetchNoise(from: startOfDay, to: now)

        let hr = await heartRate
        let rhr = await restingHR
        let hrvValue = await hrv
        let stepsValue = await steps
        let energyValue = await energy
        let exerciseValue = await exercise
        let distanceValue = await distance
        let sleepValue = await sleep
        let spo2Value = await spo2
        let noiseValue = await noise

        let activityLevel: String
        if exerciseValue >= 60 { activityLevel = "vigorous" }
        else if exerciseValue >= 30 { activityLevel = "moderate" }
        else if stepsValue >= 5000 { activityLevel = "light" }
        else { activityLevel = "sedentary" }

        let sleepQuality: String
        if sleepValue.duration >= 8 { sleepQuality = "excellent" }
        else if sleepValue.duration >= 7 { sleepQuality = "good" }
        else if sleepValue.duration >= 5 { sleepQuality = "fair" }
        else { sleepQuality = "poor" }

        let hrvTrend = "stable" // 추후 히스토리 기반 계산

        let dailyData = HealthKitDailyData(
            date: dateFormatter.string(from: now),
            heartRate: HeartRateData(
                current: hr.latest,
                resting: rhr,
                max: hr.max,
                min: hr.min,
                avg: hr.avg
            ),
            heartRateVariability: HRVData(avg: hrvValue, trend: hrvTrend),
            sleep: SleepData(
                duration: sleepValue.duration,
                deepSleep: sleepValue.deep,
                remSleep: sleepValue.rem,
                awakenings: sleepValue.awakenings,
                quality: sleepQuality
            ),
            activity: ActivityData(
                steps: stepsValue,
                distance: distanceValue,
                activeEnergy: energyValue,
                exerciseMinutes: exerciseValue,
                level: activityLevel
            ),
            oxygen: spo2Value > 0 ? OxygenData(spo2: spo2Value) : nil,
            noise: noiseValue > 0 ? NoiseData(avgDecibels: noiseValue) : nil,
            source: "native_app",
            syncedAt: ISO8601DateFormatter().string(from: Date())
        )

        todayData = dailyData

        // v3.1: 기저 심박수 업데이트 및 외부 알림
        if rhr > 40 && rhr < 120 {
            latestRestingHR = rhr
            onRestingHRUpdated?(rhr)
            print("🫀 HealthKit 기저 심박수 갱신: \(rhr) bpm → Detector/Watch 전달")
        }

        // v3.1: 일일 데이터 서버 동기화 콜백
        onDailyDataReady?(dailyData)
    }

    // MARK: - HealthKit 쿼리 헬퍼

    private func fetchHeartRateData(from: Date, to: Date) async -> (latest: Double, max: Double, min: Double, avg: Double) {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let samples = await fetchSamples(type: type, from: from, to: to)

        guard !samples.isEmpty else { return (0, 0, 0, 0) }

        let values = samples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }
        let latest = values.last ?? 0
        let max = values.max() ?? 0
        let min = values.min() ?? 0
        let avg = values.reduce(0, +) / Double(values.count)

        return (latest, max, min, avg)
    }

    private func fetchRestingHeartRate(from: Date, to: Date) async -> Double {
        let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        let samples = await fetchSamples(type: type, from: from, to: to)
        guard let latest = samples.last else { return 0 }
        return latest.quantity.doubleValue(for: HKUnit(from: "count/min"))
    }

    private func fetchHRV(from: Date, to: Date) async -> Double {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let samples = await fetchSamples(type: type, from: from, to: to)
        guard !samples.isEmpty else { return 0 }
        let values = samples.map { $0.quantity.doubleValue(for: .secondUnit(with: .milli)) }
        return values.reduce(0, +) / Double(values.count)
    }

    private func fetchSteps(from: Date, to: Date) async -> Int {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let total = await fetchCumulativeSum(type: type, from: from, to: to)
        return Int(total)
    }

    private func fetchActiveEnergy(from: Date, to: Date) async -> Double {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        return await fetchCumulativeSum(type: type, from: from, to: to, unit: .kilocalorie())
    }

    private func fetchExerciseMinutes(from: Date, to: Date) async -> Int {
        let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
        let total = await fetchCumulativeSum(type: type, from: from, to: to, unit: .minute())
        return Int(total)
    }

    private func fetchDistance(from: Date, to: Date) async -> Double {
        let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let meters = await fetchCumulativeSum(type: type, from: from, to: to, unit: .meter())
        return meters / 1000.0  // km
    }

    private func fetchSleep(from: Date, to: Date) async -> (duration: Double, deep: Double, rem: Double, awakenings: Int) {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                guard let samples = results as? [HKCategorySample] else {
                    continuation.resume(returning: (0, 0, 0, 0))
                    return
                }

                var totalSleep: TimeInterval = 0
                var deepSleep: TimeInterval = 0
                var remSleep: TimeInterval = 0
                var awakenings = 0

                for sample in samples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deepSleep += duration
                        totalSleep += duration
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        remSleep += duration
                        totalSleep += duration
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        totalSleep += duration
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awakenings += 1
                    default:
                        totalSleep += duration
                    }
                }

                continuation.resume(returning: (
                    totalSleep / 3600,
                    deepSleep / 3600,
                    remSleep / 3600,
                    awakenings
                ))
            }
            healthStore.execute(query)
        }
    }

    private func fetchSpO2(from: Date, to: Date) async -> Double {
        let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
        let samples = await fetchSamples(type: type, from: from, to: to)
        guard let latest = samples.last else { return 0 }
        return latest.quantity.doubleValue(for: .percent()) * 100
    }

    private func fetchNoise(from: Date, to: Date) async -> Double {
        let type = HKQuantityType.quantityType(forIdentifier: .environmentalAudioExposure)!
        let samples = await fetchSamples(type: type, from: from, to: to)
        guard !samples.isEmpty else { return 0 }
        let values = samples.map { $0.quantity.doubleValue(for: .decibelAWeightedSoundPressureLevel()) }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Generic Query Helpers

    private func fetchSamples(type: HKQuantityType, from: Date, to: Date) async -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, _ in
                let samples = (results as? [HKQuantitySample]) ?? []
                continuation.resume(returning: samples)
            }
            healthStore.execute(query)
        }
    }

    private func fetchCumulativeSum(type: HKQuantityType, from: Date, to: Date, unit: HKUnit = .count()) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
}
