// ============================================================================
// CareFlow Watch — API Client (iOS & watchOS 공용)
// ============================================================================
// CareFlow Next.js 서버와 통신하는 HTTP 클라이언트
// ============================================================================

import Foundation

class CareFlowAPIClient {

    // MARK: - Configuration

    private let baseURL: String
    private let timeout: TimeInterval = 30

    init(baseURL: String = "http://localhost:3000") {
        self.baseURL = baseURL
    }

    // MARK: - HealthKit 데이터 전송

    func sendHealthKitData(_ data: HealthKitDailyData) async throws -> CareFlowAPIResponse {
        let url = URL(string: "\(baseURL)/api/sensors/healthkit")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(data)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CareFlowError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CareFlowError.serverError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(CareFlowAPIResponse.self, from: responseData)
    }

    // MARK: - 어지럼증 에피소드 전송

    func sendDizzinessEpisode(_ episode: DizzinessEpisode) async throws -> CareFlowAPIResponse {
        let url = URL(string: "\(baseURL)/api/sensors/dizziness")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let payload = DizzinessEpisodePayload(from: episode)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CareFlowError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CareFlowError.serverError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(CareFlowAPIResponse.self, from: responseData)
    }

    // MARK: - 히스토리 조회

    func fetchHealthKitHistory(days: Int = 7) async throws -> [HealthKitDailyData] {
        let url = URL(string: "\(baseURL)/api/sensors/healthkit?days=\(days)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CareFlowError.invalidResponse
        }

        return try JSONDecoder().decode([HealthKitDailyData].self, from: data)
    }
}
