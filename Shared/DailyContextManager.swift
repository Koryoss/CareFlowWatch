// ============================================================================
// CareFlow Watch — Daily Context Manager
// ============================================================================
// 사용자의 일일 컨텍스트 관리 (하루 유형, 시간대, 투약 여부 등)
// iOS + watchOS 양쪽에서 사용
// ============================================================================

import Foundation
import Combine

class DailyContextManager: ObservableObject {

    // MARK: - Published

    @Published var todayDayType: DayType = .normal
    @Published var currentTimeSegment: TimeSegment = .current()
    @Published var medicationTaken: Bool = false
    @Published var currentLocationName: String?

    // MARK: - Storage Keys

    private let dayTypeKey = "careflow_day_type"
    private let medicationKey = "careflow_medication"
    private let lastDateKey = "careflow_last_date"

    // MARK: - Init

    init() {
        loadOnAppear()
    }

    // MARK: - Public Methods

    /// 앱 시작 시 저장된 상태 로드
    func loadOnAppear() {
        let today = dateString(Date())
        let lastDate = UserDefaults.standard.string(forKey: lastDateKey) ?? ""

        if today != lastDate {
            // 날짜 변경 → 리셋
            todayDayType = .normal
            medicationTaken = false
            UserDefaults.standard.set(today, forKey: lastDateKey)
            saveDayType()
            saveMedication()
        } else {
            // 기존 값 로드
            if let raw = UserDefaults.standard.string(forKey: dayTypeKey),
               let dt = DayType(rawValue: raw) {
                todayDayType = dt
            }
            medicationTaken = UserDefaults.standard.bool(forKey: medicationKey)
        }

        currentTimeSegment = .current()
    }

    /// 하루 유형 설정
    func setDayType(_ type: DayType) {
        todayDayType = type
        saveDayType()
    }

    /// 투약 기록
    func recordMedication(taken: Bool) {
        medicationTaken = taken
        saveMedication()
    }

    /// 위치 이름 업데이트
    func updateLocationName(_ name: String) {
        currentLocationName = name
    }

    /// 현재 컨텍스트 캡처
    func captureContext(note: String? = nil) -> DailyContext {
        currentTimeSegment = .current()
        return DailyContext(
            dayType: todayDayType,
            timeSegment: currentTimeSegment,
            note: note,
            medicationTaken: medicationTaken,
            locationName: currentLocationName
        )
    }

    // MARK: - Private

    private func saveDayType() {
        UserDefaults.standard.set(todayDayType.rawValue, forKey: dayTypeKey)
    }

    private func saveMedication() {
        UserDefaults.standard.set(medicationTaken, forKey: medicationKey)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
