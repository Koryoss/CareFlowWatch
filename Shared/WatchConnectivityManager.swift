// ============================================================================
// CareFlow Watch — Watch Connectivity Manager (iOS side)
// ============================================================================
// iPhone ↔ Apple Watch 실시간 통신
// Watch에서 감지된 어지럼증 에피소드를 iPhone으로 수신
// ⚠️ 이 파일은 iOS 타겟에만 포함 (watchOS 타겟 X)
// ============================================================================

import Foundation
import WatchConnectivity
import Combine

class WatchConnectivityManager: NSObject, ObservableObject {

    @Published var isReachable = false
    @Published var recentEpisodes: [DizzinessEpisode] = []
    @Published var lastMessage: String = ""

    private var session: WCSession?

    // iOS 전용 참조
    weak var contextManager: DailyContextManager?

    /// HealthKit 기저 심박수를 Watch로 전달하기 위한 콜백
    var onBaselineHRNeeded: (() -> Double)?

    override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Watch로 동기화 요청 전송
    func requestSync() {
        guard let session = session, session.isReachable else {
            lastMessage = "Apple Watch에 연결할 수 없습니다."
            return
        }

        session.sendMessage(
            [WatchMessageKey.requestSync.rawValue: true],
            replyHandler: { reply in
                DispatchQueue.main.async {
                    self.lastMessage = "동기화 완료"
                }
            },
            errorHandler: { error in
                DispatchQueue.main.async {
                    self.lastMessage = "동기화 실패: \(error.localizedDescription)"
                }
            }
        )
    }

    /// DailyContext 변경사항을 Watch로 전송
    func sendDailyContextToWatch(_ context: DailyContext) {
        guard let session = session, session.isReachable else { return }

        do {
            let data = try JSONEncoder().encode(context)
            session.sendMessage(
                [WatchMessageKey.dailyContext.rawValue: data],
                replyHandler: nil,
                errorHandler: { error in
                    print("DailyContext Watch 전송 실패: \(error)")
                }
            )
        } catch {
            print("DailyContext 인코딩 실패: \(error)")
        }
    }

    /// HealthKit 기저 심박수를 Watch Detector로 전송
    func sendBaselineHRToWatch(_ restingHR: Double) {
        guard let session = session, session.isReachable else { return }

        session.sendMessage(
            ["baseline_hr": restingHR],
            replyHandler: nil,
            errorHandler: { error in
                print("기저 심박수 Watch 전송 실패: \(error)")
            }
        )
    }

    /// 현재 위치 정보를 Watch로 전송
    func sendLocationToWatch(_ placeName: String) {
        guard let session = session, session.isReachable else { return }

        session.sendMessage(
            [WatchMessageKey.locationUpdate.rawValue: placeName],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    // MARK: - 서버 중계

    private func relayEpisodeToServer(_ episode: DizzinessEpisode) {
        Task {
            let client = CareFlowAPIClient()
            do {
                let response = try await client.sendDizzinessEpisode(episode)
                print("에피소드 서버 전송 완료: \(response.message)")
            } catch {
                print("에피소드 서버 전송 실패: \(error)")
            }
        }
    }

    func syncHealthKitDataToServer(_ data: HealthKitDailyData) {
        Task {
            let client = CareFlowAPIClient()
            do {
                let response = try await client.sendHealthKitData(data)
                print("HealthKit 데이터 서버 전송 완료: \(response.message)")
            } catch {
                print("HealthKit 데이터 서버 전송 실패: \(error)")
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = false
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {

        if let episodeData = message[WatchMessageKey.dizzinessEpisode.rawValue] as? Data {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let episode = try decoder.decode(DizzinessEpisode.self, from: episodeData)

                DispatchQueue.main.async {
                    self.recentEpisodes.insert(episode, at: 0)
                    if self.recentEpisodes.count > 50 {
                        self.recentEpisodes.removeLast()
                    }
                }

                relayEpisodeToServer(episode)
                replyHandler(["status": "received"])
            } catch {
                replyHandler(["status": "decode_error"])
            }
        }

        if let reportData = message[WatchMessageKey.manualReport.rawValue] as? Data {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let report = try decoder.decode(ManualDizzinessReport.self, from: reportData)

                var episode = DizzinessEpisode()
                episode.peakSeverity = report.severity
                episode.isManualReport = true

                DispatchQueue.main.async {
                    self.recentEpisodes.insert(episode, at: 0)
                }

                replyHandler(["status": "received"])
            } catch {
                replyHandler(["status": "decode_error"])
            }
        }
    }
}
