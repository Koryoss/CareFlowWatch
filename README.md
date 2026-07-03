# CareFlowWatch

CareFlow의 **Apple Watch · iPhone 네이티브 센서 수집 앱** (watchOS + iOS, Swift/SwiftUI).

CareFlow는 이명·어지럼 환자가 증상을 안고도 일상·사회로 복귀하도록 돕는 **비의료기기 자기관찰 도구**다. 이 워치 앱은 웹·모바일(Expo) 앱에서 불가능한 **네이티브 센서 데이터**를 수집해 개인 기준선 지표(오늘의 여유·걸음 안정도·환경 민감도)의 데이터 소스를 제공한다.

> 경계(하드룰): 진단·중증도 판정·예후 예측·치료/재활 처방을 하지 않는다. 센서 값은 임상 컷오프가 아니라 **본인 기준선 대비 관찰**에만 쓰인다.

## 구성 모듈

- **MotionSensorManager** (watchOS) — CoreMotion(CMMotionManager)으로 자이로·가속도 수집 → 걸음 안정도(IMU)
- **WatchDizzinessDetector** (watchOS) — 움직임 패턴 기반 어지럼 신호 감지
- **VoiceDecibelMonitor** (watchOS) — 음성 데시벨 기저선 학습 후 과도하게 커지면 햅틱 알림(이명 사용자 자기조절 보조)
- **HealthKitManager** (iOS) — 심박수·심박변동성(HRV) 등 HealthKit 데이터 읽기
- **LocationTracker** (공용) — 활동 범위 맥락 수집
- **CareFlowAPIClient** (공용) — CareFlow Next.js 서버로 전송하는 HTTP 클라이언트
- **WatchConnectivityManager** (공용) — Watch ↔ iPhone 데이터 동기화
- **Shared/Models** — 공용 데이터 모델

## 데이터 흐름

```
Apple Watch 센서(IMU·음성·움직임) ─┐
                                    ├─ WatchConnectivity ─ iPhone(HealthKit: HR·HRV)
                                    │                          │
                                    └──────────────────────────┴─ CareFlowAPIClient ─ CareFlow 서버(Supabase)
                                                                        └ 개인 기준선 지표로 활용
```

## 빌드 / 실행

- Xcode에서 `CareFlowWatch.xcodeproj` 열기 → watchOS/iOS 타깃 선택 후 실행
- HealthKit·CoreMotion·마이크 권한 필요(Info.plist usage description)
- 서버 주소는 `CareFlowAPIClient`에서 설정

## 상태

프로토타입. 센서 수집 모듈은 구현됐고, CareFlow 지표 파이프라인과의 실데이터 연동은 진행 중(발전보고서 참조).
