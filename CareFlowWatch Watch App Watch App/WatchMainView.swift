// ============================================================================
// CareFlow Watch — watchOS Main View (v3.1)
// ============================================================================
// Apple Watch 메인 화면: 실시간 센서 + 어지러움 보고 버튼 + 음성 피드백
//
// v3.1 수정:
//   - toggleMonitoring(): onNewDataPoint 재설정 제거 (App Entry Point 연결 보존)
//
// v3.0 추가 기능:
//   1. "어지러워요" 원터치 보고 버튼 (크고 단순한 UI)
//   2. 음성 데시벨 표시 + 자기 조절 피드백
//   3. 일상 맥락 표시 (오늘의 유형 + 시간대)
//   4. 약 복용 기록 버튼
//
// 수국 버터크림 팔레트:
//   #28C840 (accent), #3D2B1F (dark), #8B6F57 (warm), #FFFBF3 (bg)
// ============================================================================

import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct WatchMainView: View {
    @EnvironmentObject var motionManager: MotionSensorManager
    @EnvironmentObject var detector: WatchDizzinessDetector
    @EnvironmentObject var voiceMonitor: VoiceDecibelMonitor
    @EnvironmentObject var contextManager: DailyContextManager

    @State private var isActive = false
    @State private var showDayTypePicker = false
    @State private var reportConfirmed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {

                // ── 상태 헤더 ──
                StatusHeader(
                    isActive: isActive,
                    severity: detector.currentSeverity,
                    isDetecting: detector.isDetecting
                )

                // ── 일상 맥락 바 ──
                DailyContextBar(
                    contextManager: contextManager,
                    showDayTypePicker: $showDayTypePicker
                )

                // ── 🆘 어지러워요 보고 버튼 (핵심 UI) ──
                DizzinessReportButton(
                    detector: detector,
                    reportConfirmed: $reportConfirmed
                )

                // ── 음성 데시벨 표시 ──
                if voiceMonitor.isMonitoring {
                    VoiceLevelIndicator(voiceMonitor: voiceMonitor)
                }

                // ── 센서 데이터 (실시간) ──
                if isActive {
                    SensorDataView(
                        gyroMag: motionManager.gyroMagnitude,
                        tilt: motionManager.tiltAngle,
                        confidence: detector.currentConfidence
                    )
                }

                // ── 시작/중지 + 음성 모니터 토글 ──
                HStack(spacing: 8) {
                    // 모니터링 시작/중지
                    Button(action: toggleMonitoring) {
                        VStack(spacing: 2) {
                            Image(systemName: isActive ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title3)
                            Text(isActive ? "중지" : "시작")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isActive ? Color.red.opacity(0.8) : Color(hex: "#28C840"))
                        .cornerRadius(12)
                    }

                    // 음성 모니터 토글
                    Button(action: toggleVoiceMonitor) {
                        VStack(spacing: 2) {
                            Image(systemName: voiceMonitor.isMonitoring ? "mic.fill" : "mic.slash")
                                .font(.title3)
                            Text(voiceMonitor.isMonitoring ? "음성 ON" : "음성 OFF")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(voiceMonitor.isMonitoring ? Color(hex: "#8B6F57") : Color.gray.opacity(0.5))
                        .cornerRadius(12)
                    }
                }

                // ── 최근 에피소드 ──
                if !detector.episodeHistory.isEmpty {
                    RecentEpisodesView(episodes: detector.episodeHistory)
                }
            }
            .padding(.horizontal, 8)
        }
        // 알림
        .alert(detector.alertMessage, isPresented: $detector.showAlert) {
            Button("확인", role: .cancel) {}
            if detector.currentSeverity == .severe {
                Button("기록 추가", role: .none) {}
            }
        }
        // 음성 알림 (진동과 함께)
        .alert("🔊 목소리가 커지고 있어요", isPresented: $voiceMonitor.showVoiceAlert) {
            Button("알겠어요", role: .cancel) {}
        } message: {
            Text("천천히 조금 낮춰보세요.\n현재 \(Int(voiceMonitor.currentDecibel)) dB")
        }
        // 보고 완료 확인
        .alert("기록되었습니다", isPresented: $reportConfirmed) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("어지러움이 기록되었어요.\n안전한 곳에서 쉬어주세요.")
        }
        // 하루 유형 선택
        .sheet(isPresented: $showDayTypePicker) {
            DayTypePickerSheet(contextManager: contextManager, isPresented: $showDayTypePicker)
        }
    }

    private func toggleMonitoring() {
        if isActive {
            motionManager.stopMonitoring()
            isActive = false
        } else {
            // onNewDataPoint는 CareFlowWatchWatchApp.setupInterModuleConnections()에서
            // 이미 HR 포함 3-파라미터 클로저로 올바르게 설정됨 — 여기서 재설정하지 않음
            // (재설정 시 HR 파이프라인 파괴 + Swift 컴파일 에러 발생)
            motionManager.startMonitoring(frequency: .normal)
            isActive = true
        }
    }

    private func toggleVoiceMonitor() {
        if voiceMonitor.isMonitoring {
            voiceMonitor.stopMonitoring()
        } else {
            voiceMonitor.startMonitoring()
        }
    }
}

// MARK: - 🆘 어지러워요 보고 버튼

struct DizzinessReportButton: View {
    @ObservedObject var detector: WatchDizzinessDetector
    @Binding var reportConfirmed: Bool

    var body: some View {
        Button(action: {
            #if os(watchOS)
            WKInterfaceDevice.current().play(.click)
            #endif
            detector.reportDizzinessManually(severity: .moderate)
            reportConfirmed = true
        }) {
            VStack(spacing: 4) {
                Text("🌀")
                    .font(.system(size: 28))
                Text("어지러워요")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color.orange, Color.red.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 일상 맥락 바

struct DailyContextBar: View {
    @ObservedObject var contextManager: DailyContextManager
    @Binding var showDayTypePicker: Bool

    var body: some View {
        HStack(spacing: 6) {
            // 오늘의 유형
            Button(action: { showDayTypePicker = true }) {
                HStack(spacing: 3) {
                    Text(contextManager.todayDayType.emoji)
                        .font(.caption)
                    Text(contextManager.todayDayType.label)
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#3D2B1F"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.3))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            // 시간대
            HStack(spacing: 3) {
                Text(contextManager.currentTimeSegment.emoji)
                    .font(.caption)
                Text(contextManager.currentTimeSegment.label)
                    .font(.caption2)
                    .foregroundColor(Color(hex: "#8B6F57"))
            }

            Spacer()

            // 약 복용 버튼
            Button(action: {
                contextManager.recordMedication(taken: !contextManager.medicationTaken)
                #if os(watchOS)
                WKInterfaceDevice.current().play(.click)
                #endif
            }) {
                Text(contextManager.medicationTaken ? "💊✓" : "💊")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(contextManager.medicationTaken ? Color(hex: "#28C840").opacity(0.3) : Color.gray.opacity(0.2))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - 음성 레벨 표시

struct VoiceLevelIndicator: View {
    @ObservedObject var voiceMonitor: VoiceDecibelMonitor

    var body: some View {
        HStack(spacing: 8) {
            // 레벨 아이콘
            Text(voiceMonitor.currentVoiceLevel.emoji)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("음성")
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#8B6F57"))
                    Spacer()
                    Text("\(Int(voiceMonitor.currentDecibel)) dB")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(voiceLevelColor)
                }

                // 데시벨 바
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(voiceLevelColor)
                            .frame(width: geo.size.width * min(1, voiceMonitor.currentDecibel / 100))
                    }
                }
                .frame(height: 4)
            }

            if voiceMonitor.isCalibrating {
                Text("학습중")
                    .font(.system(size: 8))
                    .foregroundColor(Color(hex: "#8B6F57"))
            }
        }
        .padding(8)
        .background(voiceMonitor.showVoiceAlert ? Color.red.opacity(0.15) : Color.black.opacity(0.05))
        .cornerRadius(10)
    }

    private var voiceLevelColor: Color {
        switch voiceMonitor.currentVoiceLevel {
        case .quiet:    return Color(hex: "#28C840")
        case .normal:   return Color(hex: "#28C840")
        case .loud:     return .yellow
        case .veryLoud: return .red
        }
    }
}

// MARK: - 하루 유형 선택 시트

struct DayTypePickerSheet: View {
    @ObservedObject var contextManager: DailyContextManager
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("오늘은?")
                    .font(.headline)
                    .foregroundColor(Color(hex: "#3D2B1F"))

                ForEach(DayType.allCases, id: \.self) { type in
                    Button(action: {
                        contextManager.setDayType(type)
                        isPresented = false
                    }) {
                        HStack {
                            Text(type.emoji)
                                .font(.title3)
                            Text(type.label)
                                .font(.body)
                                .foregroundColor(Color(hex: "#3D2B1F"))
                            Spacer()
                            if contextManager.todayDayType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color(hex: "#28C840"))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            contextManager.todayDayType == type
                            ? Color(hex: "#28C840").opacity(0.15)
                            : Color.white.opacity(0.1)
                        )
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
    }
}

// MARK: - Sub Views (기존 유지 + 개선)

/// 🚦 신호등 × NANDA 분류 기반 상태 헤더
struct StatusHeader: View {
    let isActive: Bool
    let severity: DizzinessSeverity
    let isDetecting: Bool

    var body: some View {
        VStack(spacing: 4) {
            if isDetecting && severity == .severe {
                Text("🔴")
                    .font(.system(size: 36))
                Text("즉시 대응 필요")
                    .font(.headline)
                    .foregroundColor(.red)
                Text("PC: 전정기능 장애 가능성")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
            } else if isDetecting && severity == .moderate {
                Text("🟠")
                    .font(.system(size: 36))
                Text("균형감각 변화 감지")
                    .font(.headline)
                    .foregroundColor(.orange)
                Text("전정기능과 관련된 현상")
                    .font(.caption2)
                    .foregroundColor(.orange.opacity(0.8))
            } else if isDetecting {
                Text("🟡")
                    .font(.system(size: 36))
                Text("주의 신호 감지 중")
                    .font(.headline)
                    .foregroundColor(.yellow)
                Text("Risk for falls · 모니터링 강화")
                    .font(.caption2)
                    .foregroundColor(Color(hex: "#8B6F57"))
            } else if isActive {
                Text("🟢")
                    .font(.system(size: 36))
                Text("정상 모니터링 중")
                    .font(.headline)
                    .foregroundColor(Color(hex: "#28C840"))
                Text("Readiness for enhanced balance")
                    .font(.caption2)
                    .foregroundColor(Color(hex: "#8B6F57"))
            } else {
                Text("⌚")
                    .font(.system(size: 40))
                Text("CareFlow")
                    .font(.headline)
                    .foregroundColor(Color(hex: "#3D2B1F"))
                Text("모니터링을 시작하세요")
                    .font(.caption)
                    .foregroundColor(Color(hex: "#8B6F57"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

struct SensorDataView: View {
    let gyroMag: Double
    let tilt: Double
    let confidence: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                SensorMini(label: "회전", value: String(format: "%.1f", gyroMag), unit: "rad/s")
                SensorMini(label: "기울기", value: String(format: "%.0f", tilt), unit: "°")
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("감지 신뢰도")
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#8B6F57"))
                    Spacer()
                    Text("\(Int(confidence))%")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(confidenceColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(confidenceColor)
                            .frame(width: geo.size.width * min(1, confidence / 100))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.1))
        .cornerRadius(10)
    }

    private var confidenceColor: Color {
        if confidence >= 80 { return .red }
        if confidence >= 50 { return .orange }
        if confidence >= 20 { return .yellow }
        return Color(hex: "#28C840")
    }
}

struct SensorMini: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(Color(hex: "#8B6F57"))
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(Color(hex: "#8B6F57"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(Color.black.opacity(0.05))
        .cornerRadius(8)
    }
}

struct RecentEpisodesView: View {
    let episodes: [DizzinessEpisode]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("최근 기록")
                .font(.caption)
                .foregroundColor(Color(hex: "#8B6F57"))

            ForEach(episodes.prefix(3)) { episode in
                HStack {
                    Text(episode.peakSeverity.emoji)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Text(episode.durationText)
                                .font(.caption2)
                            if episode.isManualReport {
                                Text("🆘")
                                    .font(.system(size: 8))
                            }
                        }
                        // v3.0: 일상 맥락 표시
                        if let ctx = episode.dailyContext {
                            Text("\(ctx.dayType.emoji)\(ctx.timeSegment.emoji)")
                                .font(.system(size: 9))
                        }
                    }
                    Spacer()
                    Text(episode.peakSeverity.label)
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#8B6F57"))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.05))
        .cornerRadius(10)
    }
}
