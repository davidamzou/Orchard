//
//  FinnhubClient.swift
//  Orchard
//

import Foundation

/// Thin client for the Finnhub REST API (https://finnhub.io/docs/api).
/// The free plan covers US quotes, company profiles, basic financials and symbol search.
struct FinnhubClient {
    enum Failure: LocalizedError {
        case missingKey, unauthorized, notAvailableOnPlan, rateLimited, unknownSymbol(String), http(Int)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Add your Finnhub API key in Me to load live prices."
            case .unauthorized: "Finnhub rejected the API key. Check it in Me."
            case .notAvailableOnPlan: "This data isn't included in your Finnhub plan."
            case .rateLimited: "Too many requests to Finnhub. Try again in a minute."
            case .unknownSymbol(let symbol): "No quote found for \(symbol)."
            case .http(let code): "Finnhub returned an error (\(code))."
            }
        }
    }

    struct Quote: Decodable {
        let c: Double   // current
        let pc: Double  // previous close
        let t: TimeInterval
    }

    struct Profile: Decodable {
        let name: String?
        let exchange: String?
        let currency: String?
        let marketCapitalization: Double?
        let ticker: String?
    }

    struct Metrics: Decodable {
        struct Values: Decodable {
            let peTTM: Double?
            let dividendYield: Double?
            let averageVolume: Double?
            let high52Week: Double?
            let low52Week: Double?

            enum CodingKeys: String, CodingKey {
                case peTTM
                case dividendYield = "currentDividendYieldTTM"
                case averageVolume = "10DayAverageTradingVolume"
                case high52Week = "52WeekHigh"
                case low52Week = "52WeekLow"
            }
        }
        let metric: Values
    }

    struct SearchResult: Decodable, Identifiable, Hashable {
        let symbol: String
        let description: String
        let type: String
        var id: String { symbol }
    }

    private struct SearchResponse: Decodable {
        let result: [SearchResult]
    }

    static let keychainAccount = "finnhub-api-key"

    let apiKey: String
    var session: URLSession = .shared

    /// Key baked in at build time from Secrets.xcconfig, used when none is saved in the keychain.
    static var bundledKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "FinnhubAPIKey") as? String
        guard let key, !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }

    static var savedKey: String? { Keychain.string(for: keychainAccount) }

    init?(apiKey: String? = FinnhubClient.savedKey ?? FinnhubClient.bundledKey) {
        guard let apiKey, !apiKey.isEmpty else { return nil }
        self.apiKey = apiKey
    }

    func quote(_ symbol: String) async throws -> Quote {
        let quote: Quote = try await get("quote", ["symbol": symbol])
        // Finnhub answers unknown symbols with an all-zero quote.
        guard quote.t > 0 else { throw Failure.unknownSymbol(symbol) }
        return quote
    }

    func profile(_ symbol: String) async throws -> Profile {
        try await get("stock/profile2", ["symbol": symbol])
    }

    func metrics(_ symbol: String) async throws -> Metrics {
        try await get("stock/metric", ["symbol": symbol, "metric": "all"])
    }

    func search(_ query: String) async throws -> [SearchResult] {
        let response: SearchResponse = try await get("search", ["q": query, "exchange": "US"])
        return response.result.filter { !$0.symbol.contains(".") }
    }

    private func get<T: Decodable>(_ path: String, _ parameters: [String: String]) async throws -> T {
        var components = URLComponents(string: "https://finnhub.io/api/v1/\(path)")!
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return try JSONDecoder().decode(T.self, from: data)
        case 401: throw Failure.unauthorized
        case 403: throw Failure.notAvailableOnPlan
        case 429: throw Failure.rateLimited
        default: throw Failure.http(status)
        }
    }
}
