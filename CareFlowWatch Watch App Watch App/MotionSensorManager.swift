// ============================================================================
// CareFlow Watch — Motion Sensor Manager (watchOS)
// ============================================================================
// Apple Watch의 CMMotionManager를 사용해 자이로/가속도 데이터 수집
//
// 핵심: 이것이 네이티브 앱에서만 가능한 이유!
//   - CMMotionManager는 CoreMotion 프레임워크 (네이티브 전용)
//   - watchOS에서 직접 센서 접근 가능
//   - 웹 앱(Safari)에서는 접근 불가 ❌
//
// 센서 스펙 (Apple Watch):
//   - 자이로스코프: ±2000 deg/s
//   - 가속도계: ±16g
//   - 샘플링: 최대 100Hz
// ============================================================================

import Foundation
import CoreMotion
import Combine

class MotionSensorManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isMonitoring = false
    @Published var currentGyro: GyroscopeData = GyroscopeData(x: 0, y: 0, z: 0)
    @Published var currentAccel: AccelerometerData = AccelerometerData(x: 0, y: 0, z: 0)
    @Published var currentHeartRate: Double = 0
    @Published var gyroMagnitude: Double = 0
    @Published var tiltAngle: Double = 0

    // MARK: - Private

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    /// 센서 업데이트 간격 (초) — 1Hz (배터리 절약) or 10Hz (정밀 모니터링)
    private var updateInterval: TimeInterval = 1.0 / 10.0  // 10Hz

    /// 데이터 콜백 — v3.1: HR 포함 (이전: gyro, accel만 전달)
    /// MotionSensor가 gyro/accel 수집 → 최신 HR과 함께 Detector로 전달
    var onNewDataPoint: ((GyroscopeData, AccelerometerData, Double) -> Void)?

    // MARK: - 실시간 심박수 업데이트 (v3.1)

    /// HealthKit workout session 또는 HKAnchoredObjectQuery에서 갱신
    func updateHeartRate(_ hr: Double) {
        DispatchQueue.main.async {
            self.currentHeartRate = hr
        }
    }

    // MARK: - Init

    init() {
        queue.name = "CareFlow.MotionSensor"
        queue.maxConcurrentOperationCount = 1
    }

    // MARK: - 센서 모니터링 시작/중지

    /// 자이로 + 가속도계 동시 수집 시작
    func startMonitoring(frequency: SensorFrequency = .normal) {
        guard motionManager.isDeviceMotionAvailable else {
            print("⚠️ DeviceMotion 사용 불가")
            return
        }

        updateInterval = frequency.interval
        motionManager.deviceMotionUpdateInterval = updateInterval

        // DeviceMotion = 자이로 + 가속도 + 자세 통합 데이터
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: queue
        ) { [weak self] motion, error in
            guard let self = self, let motion = motion else {
                if let error = error {
                    print("센서 오류: \(error)")
                }
                return
            }

            // 자이로스코프 데이터 (rad/s)
            let gyro = GyroscopeData(
                x: motion.rotationRate.x,
                y: motion.rotationRate.y,
                z: motion.rotationRate.z
            )

            // 가속도계 데이터 (g) — userAcceleration = 중력 제거된 순수 가속도
            // gravity + userAcceleration = 전체 가속도
            let accel = AccelerometerData(
                x: motion.gravity.x + motion.userAcceleration.x,
                y: motion.gravity.y + motion.userAcceleration.y,
                z: motion.gravity.z + motion.userAcceleration.z
            )

            DispatchQueue.main.async {
                self.currentGyro = gyro
                self.currentAccel = accel
                self.gyroMagnitude = gyro.magnitude
                self.tiltAngle = accel.tilt
                self.isMonitoring = true
            }

            // 외부 콜백 — v3.1: 현재 HR도 함께 전달
            self.onNewDataPoint?(gyro, accel, self.currentHeartRate)
        }

        DispatchQueue.main.async {
            self.isMonitoring = true
        }

        print("✅ 센서 모니터링 시작 (\(frequency.label))")
    }

    /// 센서 수집 중지
    func stopMonitoring() {
        motionManager.stopDeviceMotionUpdates()

        DispatchQueue.main.async {
            self.isMonitoring = false
        }

        print("⏹ 센서 모니터링 중지")
    }

    /// 주파수 변경 (배터리 상태에 따라)
    func changeFrequency(_ frequency: SensorFrequency) {
        if isMonitoring {
            stopMonitoring()
            startMonitoring(frequency: frequency)
        }
    }

    // MARK: - 센서 가용성 확인

    var isGyroAvailable: Bool { motionManager.isGyroAvailable }
    var isAccelAvailable: Bool { motionManager.isAccelerometerAvailable }
    var isDeviceMotionAvailable: Bool { motionManager.isDeviceMotionAvailable }
}

// MARK: - 센서 주파수

enum SensorFrequency {
    case low       // 1Hz — 배터리 절약 모드
    case normal    // 10Hz — 일반 모니터링
    case high      // 50Hz — 정밀 감지 모드

    var interval: TimeInterval {
        switch self {
        case .low: return 1.0
        case .normal: return 1.0 / 10.0
        case .high: return 1.0 / 50.0
        }
    }

    var label: String {
        switch self {
        case .low: return "1Hz (절약)"
        case .normal: return "10Hz (일반)"
        case .high: return "50Hz (정밀)"
        }
    }
}
