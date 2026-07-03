// ============================================================================
// CareFlow Watch — Location Tracker (iOS)
// ============================================================================
// 위치 추적 및 장소 이름 제공 (역지오코딩)
// v3.1: DailyContext에 장소 정보 제공
// ============================================================================

import Foundation
import CoreLocation
import Combine

class LocationTracker: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentPlaceForContext: String?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // MARK: - Private Properties
    
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100  // 100m 이동 시에만 업데이트
    }
    
    // MARK: - Public Methods
    
    func requestAuthorization() {
        authorizationStatus = locationManager.authorizationStatus
        
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startTracking()
        case .denied, .restricted:
            print("⚠️ 위치 권한이 거부되었습니다")
        @unknown default:
            break
        }
    }
    
    func startTracking() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("⚠️ 위치 권한 없음 — 추적 불가")
            return
        }
        
        locationManager.startUpdatingLocation()
        print("📍 위치 추적 시작")
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        print("📍 위치 추적 중지")
    }
    
    // MARK: - Private Methods
    
    private func reverseGeocode(_ location: CLLocation) {
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first, error == nil else {
                print("⚠️ 역지오코딩 실패: \(error?.localizedDescription ?? "알 수 없는 오류")")
                return
            }
            
            // 장소 이름 생성
            let placeName = self?.formatPlaceName(from: placemark) ?? "알 수 없는 장소"
            
            DispatchQueue.main.async {
                self?.currentPlaceForContext = placeName
                print("📍 현재 위치: \(placeName)")
            }
        }
    }
    
    private func formatPlaceName(from placemark: CLPlacemark) -> String {
        // 우선순위: 1. 장소명 2. 동/리 3. 구 4. 시
        if let name = placemark.name, !name.isEmpty {
            return name
        }
        
        if let subLocality = placemark.subLocality {
            return subLocality
        }
        
        if let locality = placemark.locality {
            return locality
        }
        
        return placemark.administrativeArea ?? "현재 위치"
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTracker: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // 이전 위치와 너무 가까우면 무시 (배터리 절약)
        if let last = lastLocation, last.distance(from: location) < 100 {
            return
        }
        
        lastLocation = location
        reverseGeocode(location)
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
        
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            startTracking()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("⚠️ 위치 업데이트 실패: \(error.localizedDescription)")
    }
}
