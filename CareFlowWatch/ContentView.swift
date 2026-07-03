// ============================================================================
// CareFlow Watch — iOS Main View (v3.1)
// ============================================================================
// iPhone 메인 화면: 건강 데이터 + 일상 기록 + 장소 지도 + 에피소드 기록
//
// v3.0 추가:
//   1. 일상 기록 카드 (업무일/집/외출 + 시간대 + 약 복용)
//   2. 자주 방문하는 장소 지도 (MapKit)
//   3. 에피소드에 일상 맥락 표시
// ============================================================================

import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var contextManager: DailyContextManager
    @EnvironmentObject var locationTracker: LocationTracker
    @State private var serverConnected = false
    @State private var showingAlert = false
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                // 탭 1: 메인 (건강 + 기록)
                mainTab
                    .tabItem {
                        Image(systemName: "heart.text.square")
                        Text("홈")
                    }
                    .tag(0)

                // 탭 2: 일상 기록
                dailyTrackingTab
                    .tabItem {
                        Image(systemName: "calendar.badge.clock")
                        Text("일상 기록")
                    }
                    .tag(1)

                // 탭 3: 장소 지도
                locationMapTab
                    .tabItem {
                        Image(systemName: "map")
                        Text("장소")
                    }
                    .tag(2)
            }
            .accentColor(Color(hex: "#28C840"))
        }
    }

    // MARK: - 탭 1: 메인

    private var mainTab: some View {
        ScrollView {
            VStack(spacing: 20) {

                // 연결 상태
                ConnectionStatusCard(
                    watchConnected: connectivity.isReachable,
                    serverConnected: serverConnected
                )

                // 오늘의 일상 맥락 요약
                DailyContextSummaryCard(contextManager: contextManager)

                // 오늘의 건강 요약
                if let today = healthKit.todayData {
                    HealthSummaryCard(data: today)
                } else {
                    EmptyHealthCard()
                }

                // 최근 어지럼증 에피소드
                RecentEpisodesCard(episodes: connectivity.recentEpisodes)

                // 동기화 버튼
                Button(action: syncData) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("지금 동기화")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "#28C840"))
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .font(.headline)
                }

                // HealthKit 권한 요청
                if !healthKit.isAuthorized {
                    Button(action: requestPermissions) {
                        HStack {
                            Image(systemName: "heart.fill")
                            Text("건강 데이터 접근 허용")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "#8B6F57"))
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .font(.headline)
                    }
                }
            }
            .padding()
        }
        .background(Color(hex: "#FFFBF3"))
        .navigationTitle("CareFlow")
        .onAppear {
            checkServerStatus()
            contextManager.loadOnAppear()
            locationTracker.requestCurrentLocation()
        }
    }

    // MARK: - 탭 2: 일상 기록

    private var dailyTrackingTab: some View {
        ScrollView {
            VStack(spacing: 16) {

                // 오늘의 유형 선택
                VStack(alignment: .leading, spacing: 12) {
                    Text("오늘은 어떤 날인가요?")
                        .font(.headline)
                        .foregroundColor(Color(hex: "#3D2B1F"))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(DayType.allCases, id: \.self) { type in
                            Button(action: { contextManager.setDayType(type) }) {
                                VStack(spacing: 6) {
                                    Text(type.emoji)
                                        .font(.title)
                                    Text(type.label)
                                        .font(.subheadline)
                                        .foregroundColor(Color(hex: "#3D2B1F"))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    contextManager.todayDayType == type
                                    ? Color(hex: "#28C840").opacity(0.15)
                                    : Color.white
                                )
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            contextManager.todayDayType == type
                                            ? Color(hex: "#28C840")
                                            : Color(hex: "#EAD9BA"),
                                            lineWidth: contextManager.todayDayType == type ? 2 : 1
                                        )
                                )
                            }
                        }
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8)

                // 현재 시간대
                VStack(alignment: .leading, spacing: 12) {
                    Text("현재 시간대")
                        .font(.headline)
                        .foregroundColor(Color(hex: "#3D2B1F"))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TimeSegment.allCases, id: \.self) { seg in
                                VStack(spacing: 4) {
                                    Text(seg.emoji)
                                        .font(.title2)
                                    Text(seg.label)
                                        .font(.caption)
                                        .foregroundColor(Color(hex: "#3D2B1F"))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    contextManager.currentTimeSegment == seg
                                    ? Color(hex: "#28C840").opacity(0.2)
                                    : Color(hex: "#FFF8EC")
                                )
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            contextManager.currentTimeSegment == seg
                                            ? Color(hex: "#28C840") : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                            }
                        }
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8)

                // 약 복용 기록
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("오늘 약 복용")
                            .font(.headline)
                            .foregroundColor(Color(hex: "#3D2B1F"))
                        Text("의사선생님이 처방해 주신 약")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#8B6F57"))
                    }
                    Spacer()
                    Button(action: {
                        contextManager.recordMedication(taken: !contextManager.medicationTaken)
                    }) {
                        HStack {
                            Image(systemName: contextManager.medicationTaken ? "checkmark.circle.fill" : "circle")
                            Text(contextManager.medicationTaken ? "복용 완료" : "미복용")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            contextManager.medicationTaken
                            ? Color(hex: "#28C840").opacity(0.15)
                            : Color(hex: "#FFF8EC")
                        )
                        .foregroundColor(
                            contextManager.medicationTaken
                            ? Color(hex: "#28C840")
                            : Color(hex: "#8B6F57")
                        )
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8)

                // 오늘 기록 저장
                Button(action: { contextManager.saveToday() }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("오늘 기록 저장")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "#8B6F57"))
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .font(.headline)
                }
            }
            .padding()
        }
        .background(Color(hex: "#FFFBF3"))
        .navigationTitle("일상 기록")
    }

    // MARK: - 탭 3: 장소 지도

    private var locationMapTab: some View {
        VStack(spacing: 0) {
            // 지도
            if !locationTracker.frequentPlaces.isEmpty {
                Map(coordinateRegion: .constant(mapRegion), annotationItems: locationTracker.frequentPlaces) { place in
                    MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)) {
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .fill(place.episodesHere > 0 ? Color.red.opacity(0.3) : Color(hex: "#28C840").opacity(0.3))
                                    .frame(width: CGFloat(20 + place.visitCount * 2), height: CGFloat(20 + place.visitCount * 2))
                                Text(place.episodesHere > 0 ? "🔴" : "📍")
                                    .font(.caption)
                            }
                            Text(place.name)
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "#3D2B1F"))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(4)
                        }
                    }
                }
                .frame(height: 300)
                .cornerRadius(16)
                .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundColor(Color(hex: "#EAD9BA"))
                    Text("아직 방문 기록이 없습니다")
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "#8B6F57"))
                    if !locationTracker.isAuthorized {
                        Button("위치 접근 허용") {
                            locationTracker.requestAuthorization()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#28C840"))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            }

            // 장소 목록
            ScrollView {
                VStack(spacing: 8) {
                    HStack {
                        Text("자주 방문하는 장소")
                            .font(.headline)
                            .foregroundColor(Color(hex: "#3D2B1F"))
                        Spacer()
                        Text("\(locationTracker.frequentPlaces.count)곳")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#8B6F57"))
                    }
                    .padding(.horizontal)

                    ForEach(locationTracker.frequentPlaces.sorted(by: { $0.visitCount > $1.visitCount })) { place in
                        HStack {
                            Text("📍")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.subheadline)
                                    .foregroundColor(Color(hex: "#3D2B1F"))
                                Text("방문 \(place.visitCount)회 · 에피소드 \(place.episodesHere)회")
                                    .font(.caption)
                                    .foregroundColor(Color(hex: "#8B6F57"))
                            }
                            Spacer()
                            if place.episodesHere > 0 {
                                Text("⚠️")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical)
            }
        }
        .background(Color(hex: "#FFFBF3"))
        .navigationTitle("장소")
    }

    // MARK: - Map Region

    private var mapRegion: MKCoordinateRegion {
        if let first = locationTracker.frequentPlaces.first {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        // 서울 기본값
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }

    // MARK: - Actions

    private func syncData() {
        Task {
            await healthKit.fetchTodayData()
            if let data = healthKit.todayData {
                let client = CareFlowAPIClient()
                do {
                    let _ = try await client.sendHealthKitData(data)
                } catch {
                    print("동기화 실패: \(error)")
                }
            }
        }
    }

    private func requestPermissions() {
        healthKit.requestAuthorization()
    }

    private func checkServerStatus() {
        Task {
            let client = CareFlowAPIClient()
            serverConnected = await client.checkServerStatus()
        }
    }
}

// MARK: - 일상 맥락 요약 카드

struct DailyContextSummaryCard: View {
    @ObservedObject var contextManager: DailyContextManager

    var body: some View {
        HStack(spacing: 12) {
            // 오늘 유형
            VStack(spacing: 4) {
                Text(contextManager.todayDayType.emoji)
                    .font(.title2)
                Text(contextManager.todayDayType.label)
                    .font(.caption)
                    .foregroundColor(Color(hex: "#3D2B1F"))
            }

            Divider().frame(height: 40)

            // 시간대
            VStack(spacing: 4) {
                Text(contextManager.currentTimeSegment.emoji)
                    .font(.title2)
                Text(contextManager.currentTimeSegment.label)
                    .font(.caption)
                    .foregroundColor(Color(hex: "#3D2B1F"))
            }

            Divider().frame(height: 40)

            // 약 복용
            VStack(spacing: 4) {
                Text(contextManager.medicationTaken ? "💊✓" : "💊")
                    .font(.title2)
                Text(contextManager.medicationTaken ? "복용" : "미복용")
                    .font(.caption)
                    .foregroundColor(contextManager.medicationTaken ? Color(hex: "#28C840") : Color(hex: "#8B6F57"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
}

// MARK: - Sub Views (기존 유지)

struct ConnectionStatusCard: View {
    let watchConnected: Bool
    let serverConnected: Bool

    var body: some View {
        HStack(spacing: 16) {
            StatusDot(label: "Apple Watch", connected: watchConnected, icon: "applewatch")
            Divider().frame(height: 40)
            StatusDot(label: "CareFlow 서버", connected: serverConnected, icon: "server.rack")
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
}

struct StatusDot: View {
    let label: String
    let connected: Bool
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Color(hex: "#8B6F57"))
            VStack(alignment: .leading) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(Color(hex: "#8B6F57"))
                HStack(spacing: 4) {
                    Circle()
                        .fill(connected ? Color(hex: "#28C840") : Color.red)
                        .frame(width: 8, height: 8)
                    Text(connected ? "연결됨" : "끊김")
                        .font(.caption2)
                        .foregroundColor(connected ? Color(hex: "#28C840") : .red)
                }
            }
        }
    }
}

struct HealthSummaryCard: View {
    let data: HealthKitDailyData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("오늘의 건강")
                .font(.headline)
                .foregroundColor(Color(hex: "#3D2B1F"))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MiniCard(icon: "🫀", label: "심박", value: "\(Int(data.heartRate.avg))", unit: "bpm")
                MiniCard(icon: "😴", label: "수면", value: String(format: "%.1f", data.sleep.duration), unit: "시간")
                MiniCard(icon: "🚶", label: "걸음", value: "\(data.activity.steps)", unit: "")
                MiniCard(icon: "💪", label: "운동", value: "\(data.activity.exerciseMinutes)", unit: "분")
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
}

struct MiniCard: View {
    let icon: String
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.title2)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Color(hex: "#3D2B1F"))
            Text("\(label) \(unit)")
                .font(.caption2)
                .foregroundColor(Color(hex: "#8B6F57"))
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(hex: "#FFF8EC"))
        .cornerRadius(12)
    }
}

struct EmptyHealthCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.square")
                .font(.largeTitle)
                .foregroundColor(Color(hex: "#EAD9BA"))
            Text("건강 데이터가 아직 없습니다")
                .font(.subheadline)
                .foregroundColor(Color(hex: "#8B6F57"))
            Text("Apple Watch를 착용하고 동기화해주세요")
                .font(.caption)
                .foregroundColor(Color(hex: "#EAD9BA"))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .cornerRadius(16)
    }
}

/// 🚦 v4.1 최근 현상 기록 카드 — v3.0 일상 맥락 추가
struct RecentEpisodesCard: View {
    let episodes: [DizzinessEpisode]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("최근 관찰 기록")
                    .font(.headline)
                    .foregroundColor(Color(hex: "#3D2B1F"))
                Spacer()
                Text("🚦 NANDA")
                    .font(.caption2)
                    .foregroundColor(Color(hex: "#8B6F57"))
            }

            if episodes.isEmpty {
                VStack(spacing: 4) {
                    Text("🟢")
                        .font(.title2)
                    Text("관찰된 현상 없음")
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "#8B6F57"))
                    Text("Readiness for enhanced balance")
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#EAD9BA"))
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(episodes.prefix(5)) { episode in
                    HStack {
                        Text(episode.peakSeverity.emoji)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(phenomenonDescription(for: episode))
                                    .font(.subheadline)
                                    .foregroundColor(Color(hex: "#3D2B1F"))
                                if episode.isManualReport {
                                    Text("🆘")
                                        .font(.caption2)
                                }
                            }
                            HStack(spacing: 4) {
                                Text("\(episode.durationText) · \(episode.timeOfDay.label)")
                                    .font(.caption)
                                    .foregroundColor(Color(hex: "#8B6F57"))
                                // v3.0: 일상 맥락 표시
                                if let ctx = episode.dailyContext {
                                    Text("\(ctx.dayType.emoji)\(ctx.timeSegment.emoji)")
                                        .font(.caption2)
                                }
                            }
                        }
                        Spacer()
                        Text(episode.peakSeverity.label)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(severityBackground(for: episode.peakSeverity))
                            .cornerRadius(8)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }

    private func phenomenonDescription(for episode: DizzinessEpisode) -> String {
        if !episode.triggerEstimate.isEmpty {
            return episode.triggerEstimate
        }
        switch episode.peakSeverity {
        case .none:     return "정상 범위 내 움직임"
        case .mild:     return "균형감각 변화 가능성 관찰"
        case .moderate: return "전정기능과 관련된 균형 변화"
        case .severe:   return "PC: 즉각적 의료 평가 필요"
        }
    }

    private func severityBackground(for severity: DizzinessSeverity) -> Color {
        switch severity {
        case .none:     return Color(hex: "#E8F8EC")
        case .mild:     return Color(hex: "#FFFCE0")
        case .moderate: return Color(hex: "#FFF0E0")
        case .severe:   return Color(hex: "#FFE8E8")
        }
    }
}

// Color(hex:) extension → Shared/Extensions.swift로 이동됨
