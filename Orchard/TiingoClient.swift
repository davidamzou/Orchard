//
//  TiingoClient.swift
//  Orchard
//

import Foundation

/// Daily price history from Tiingo (https://www.tiingo.com/documentation/end-of-day).
/// The free plan allows 50 requests an hour and 1,000 a day, for personal use.
struct TiingoClient {
    enum Failure: LocalizedError {
        case unauthorized, rateLimited, unknownSymbol(String), http(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "Tiingo rejected the token. Check it in Me."
            case .rateLimited: "Tiingo's hourly limit was reached. History will load later."
            case .unknownSymbol(let symbol): "Tiingo has no history for \(symbol)."
            case .http(let code): "Tiingo returned an error (\(code))."
            }
        }
    }

    struct Bar: Decodable {
        let date: Date
        let adjClose: Double
    }

    let apiKey: String
    var session: URLSession = .shared

    static let keychainAccount = "tiingo-api-token"

    /// The token the user entered in Me, kept in the keychain.
    static var savedKey: String? { Keychain.string(for: keychainAccount) }

    init?(apiKey: String? = TiingoClient.savedKey) {
        guard let apiKey, !apiKey.isEmpty else { return nil }
        self.apiKey = apiKey
    }

    /// Daily adjusted closes from `start` to today, oldest first.
    func dailyCloses(_ symbol: String, since start: Date) async throws -> [Bar] {
        var components = URLComponents(string: "https://api.tiingo.com/tiingo/daily/\(symbol.lowercased())/prices")!
        components.queryItems = [
            URLQueryItem(name: "startDate", value: start.formatted(.iso8601.year().month().day())),
            URLQueryItem(name: "resampleFreq", value: "daily"),
            URLQueryItem(name: "columns", value: "date,adjClose"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let text = try decoder.singleValueContainer().decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
                }
                return date
            }
            return try decoder.decode([Bar].self, from: data)
        case 401, 403: throw Failure.unauthorized
        case 404: throw Failure.unknownSymbol(symbol)
        case 429: throw Failure.rateLimited
        case let code: throw Failure.http(code)
        }
    }
}
