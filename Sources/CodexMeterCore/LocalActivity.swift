import Foundation

public struct TokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int64
    public var cachedInputTokens: Int64
    public var outputTokens: Int64
    public var totalTokens: Int64

    public init(inputTokens: Int64 = 0, cachedInputTokens: Int64 = 0, outputTokens: Int64 = 0, totalTokens: Int64 = 0) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            inputTokens: saturatedAdd(lhs.inputTokens, rhs.inputTokens),
            cachedInputTokens: saturatedAdd(lhs.cachedInputTokens, rhs.cachedInputTokens),
            outputTokens: saturatedAdd(lhs.outputTokens, rhs.outputTokens),
            totalTokens: saturatedAdd(lhs.totalTokens, rhs.totalTokens)
        )
    }

    private static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int64.max : result.partialValue
    }

    fileprivate func isAtLeast(_ other: Self) -> Bool {
        inputTokens >= other.inputTokens
            && cachedInputTokens >= other.cachedInputTokens
            && outputTokens >= other.outputTokens
            && totalTokens >= other.totalTokens
    }

    fileprivate static func delta(from previous: Self, to current: Self) -> Self {
        Self(
            inputTokens: current.inputTokens - previous.inputTokens,
            cachedInputTokens: current.cachedInputTokens - previous.cachedInputTokens,
            outputTokens: current.outputTokens - previous.outputTokens,
            totalTokens: current.totalTokens - previous.totalTokens
        )
    }

    fileprivate var fingerprint: String {
        "\(inputTokens):\(cachedInputTokens):\(outputTokens):\(totalTokens)"
    }
}

public enum LocalActivityError: LocalizedError, Equatable {
    case unreadableSource
    case filterUnavailable
    case filterFailed
    case unsupportedRecords
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .unreadableSource: return "Local Codex session history is not readable."
        case .filterUnavailable: return "The local history filter could not be started."
        case .filterFailed: return "Local Codex session history could not be filtered."
        case .unsupportedRecords: return "Codex returned an unsupported local usage record format."
        case .timedOut: return "This Mac activity scan took too long and was stopped. Try Refresh again after closing inactive Codex tasks."
        }
    }
}

public struct DailyTokenUsage: Codable, Equatable, Identifiable, Sendable {
    public let date: Date
    public let usage: TokenUsage
    public var id: Date { date }

    public init(date: Date, usage: TokenUsage) {
        self.date = date
        self.usage = usage
    }
}

public struct ModelTokenUsage: Codable, Equatable, Identifiable, Sendable {
    public let model: String
    public let usage: TokenUsage
    public var id: String { model }

    public init(model: String, usage: TokenUsage) {
        self.model = model
        self.usage = usage
    }
}

public struct LocalActivitySnapshot: Codable, Equatable, Sendable {
    public let days: [DailyTokenUsage]
    public let models: [ModelTokenUsage]
    public let sampledAt: Date
    public let filesRead: Int
    public let summarizedLargeFiles: Int

    public init(
        days: [DailyTokenUsage],
        models: [ModelTokenUsage] = [],
        sampledAt: Date,
        filesRead: Int,
        summarizedLargeFiles: Int = 0
    ) {
        self.days = days
        self.models = models
        self.sampledAt = sampledAt
        self.filesRead = filesRead
        self.summarizedLargeFiles = summarizedLargeFiles
    }

    public var total: TokenUsage { days.reduce(TokenUsage()) { $0 + $1.usage } }
    public var today: TokenUsage { days.last?.usage ?? TokenUsage() }
}

public struct ModelPrice: Codable, Equatable, Identifiable, Sendable {
    public let model: String
    public let inputPerMillion: Double
    public let cachedInputPerMillion: Double
    public let outputPerMillion: Double
    public var id: String { model }

    public init(model: String, inputPerMillion: Double, cachedInputPerMillion: Double, outputPerMillion: Double) {
        self.model = model
        self.inputPerMillion = inputPerMillion
        self.cachedInputPerMillion = cachedInputPerMillion
        self.outputPerMillion = outputPerMillion
    }

    public func estimate(_ usage: TokenUsage) -> Double {
        LocalCostRates(inputPerMillion: inputPerMillion, cachedInputPerMillion: cachedInputPerMillion, outputPerMillion: outputPerMillion).estimate(usage)
    }
}

public enum OpenAIPriceCatalog {
    public static let effectiveDate = "2026-08-24"
    public static let sourceURL = URL(string: "https://developers.openai.com/api/docs/models")!
    public static let prices: [ModelPrice] = [
        .init(model: "gpt-5.6-sol", inputPerMillion: 4, cachedInputPerMillion: 0.4, outputPerMillion: 20),
        .init(model: "gpt-5.6", inputPerMillion: 4, cachedInputPerMillion: 0.4, outputPerMillion: 20),
        .init(model: "gpt-5.6-terra", inputPerMillion: 2, cachedInputPerMillion: 0.2, outputPerMillion: 12),
        .init(model: "gpt-5.6-luna", inputPerMillion: 0.2, cachedInputPerMillion: 0.02, outputPerMillion: 1.2),
        .init(model: "gpt-5.5", inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30),
        .init(model: "gpt-5.4", inputPerMillion: 2.5, cachedInputPerMillion: 0.25, outputPerMillion: 15),
        .init(model: "gpt-5.4-mini", inputPerMillion: 0.75, cachedInputPerMillion: 0.075, outputPerMillion: 4.5)
    ]

    public static func price(for model: String) -> ModelPrice? {
        prices.first { $0.model == model }
    }

    public static func estimate(_ models: [ModelTokenUsage]) -> Double {
        models.reduce(0) { total, item in total + (price(for: item.model)?.estimate(item.usage) ?? 0) }
    }
}

public enum DisplayCurrency: String, Codable, CaseIterable, Identifiable, Sendable {
    case usd = "USD"
    case aud = "AUD"
    case eur = "EUR"

    public var id: String { rawValue }
    public var code: String { rawValue }

    public var symbol: String {
        switch self {
        case .usd: return "US$"
        case .aud: return "A$"
        case .eur: return "€"
        }
    }

    public var bundledUSDExchangeRate: Double {
        switch self {
        case .usd: return 1
        case .aud: return 1.6428 / 1.1405
        case .eur: return 1 / 1.1405
        }
    }

    public func convertFromUSD(_ amount: Double, overrideRate: Double? = nil) -> Double {
        amount * (overrideRate ?? bundledUSDExchangeRate)
    }
}

public enum CurrencyRateCatalog {
    public static let effectiveDate = "2026-07-14"
    public static let sourceURL = URL(string: "https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html")!
}

public struct LocalCostRates: Codable, Equatable, Sendable {
    public var inputPerMillion: Double
    public var cachedInputPerMillion: Double
    public var outputPerMillion: Double

    public init(inputPerMillion: Double, cachedInputPerMillion: Double, outputPerMillion: Double) {
        self.inputPerMillion = max(0, inputPerMillion)
        self.cachedInputPerMillion = max(0, cachedInputPerMillion)
        self.outputPerMillion = max(0, outputPerMillion)
    }

    public var isConfigured: Bool { inputPerMillion > 0 || cachedInputPerMillion > 0 || outputPerMillion > 0 }

    public func estimate(_ usage: TokenUsage) -> Double {
        let nonCached = max(0, usage.inputTokens - usage.cachedInputTokens)
        return Double(nonCached) / 1_000_000 * inputPerMillion
            + Double(usage.cachedInputTokens) / 1_000_000 * cachedInputPerMillion
            + Double(usage.outputTokens) / 1_000_000 * outputPerMillion
    }
}

public actor LocalActivityScanner {
    private struct CumulativeRecord: Sendable {
        let date: Date
        let total: TokenUsage
        let model: String?
    }

    private struct Event: Sendable {
        let date: Date
        let usage: TokenUsage
        let model: String
        let fingerprint: String
    }

    private var cachedSignature: String?
    private var cachedEvents: [Event] = []
    private let roots: [URL]
    private let calendar: Calendar
    private let largeFileThresholdBytes: Int
    private let largeFileTailBytes: Int
    private let fractionalISO = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private let standardISO = Date.ISO8601FormatStyle()

    public init(
        roots: [URL]? = nil,
        calendar: Calendar = .current,
        largeFileThresholdBytes: Int = 128 * 1_024 * 1_024,
        largeFileTailBytes: Int = 32 * 1_024 * 1_024
    ) {
        if let roots {
            self.roots = roots
        } else {
            let codex = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
            self.roots = [
                codex.appendingPathComponent("sessions", isDirectory: true),
                codex.appendingPathComponent("archived_sessions", isDirectory: true)
            ]
        }
        self.calendar = calendar
        self.largeFileThresholdBytes = max(1, largeFileThresholdBytes)
        self.largeFileTailBytes = max(1_024, largeFileTailBytes)
    }

    public func scan(days dayCount: Int = 7, now: Date = Date()) async throws -> LocalActivitySnapshot {
        let days = max(1, min(90, dayCount))
        let startToday = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: startToday) ?? startToday
        let candidates = try discoverFiles(modifiedSince: calendar.date(byAdding: .day, value: -1, to: cutoff) ?? cutoff)
        let signature = candidates.compactMap { url -> String? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let modifiedAt = values.contentModificationDate else { return nil }
            return "\(url.path):\(size):\(modifiedAt.timeIntervalSince1970)"
        }.joined(separator: "|")
        let allEvents: [Event]
        let summarizedLargeFiles: Int
        if signature == cachedSignature {
            allEvents = cachedEvents
            summarizedLargeFiles = candidates.filter { url in
                (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > largeFileThresholdBytes
            }.count
        } else {
            let result = try await readEvents(from: candidates, cutoff: cutoff)
            allEvents = result.events
            summarizedLargeFiles = result.summarizedLargeFiles
            cachedSignature = signature
            cachedEvents = allEvents
        }

        var seen = Set<String>()
        var buckets: [Date: TokenUsage] = [:]
        var modelBuckets: [String: TokenUsage] = [:]
        for event in allEvents where event.date >= cutoff && event.date <= now {
            guard seen.insert(event.fingerprint).inserted else { continue }
            let day = calendar.startOfDay(for: event.date)
            buckets[day] = (buckets[day] ?? TokenUsage()) + event.usage
            modelBuckets[event.model] = (modelBuckets[event.model] ?? TokenUsage()) + event.usage
        }

        let output = (0..<days).compactMap { offset -> DailyTokenUsage? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: cutoff) else { return nil }
            return DailyTokenUsage(date: date, usage: buckets[date] ?? TokenUsage())
        }
        var modelOutput = modelBuckets.map { key, value in ModelTokenUsage(model: key, usage: value) }
        modelOutput.sort { lhs, rhs in
            if lhs.usage.totalTokens == rhs.usage.totalTokens { return lhs.model < rhs.model }
            return lhs.usage.totalTokens > rhs.usage.totalTokens
        }
        return LocalActivitySnapshot(
            days: output,
            models: modelOutput,
            sampledAt: now,
            filesRead: candidates.count,
            summarizedLargeFiles: summarizedLargeFiles
        )
    }

    private func discoverFiles(modifiedSince cutoff: Date) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        var urls: [URL] = []
        for root in roots {
            if FileManager.default.fileExists(atPath: root.path), !FileManager.default.isReadableFile(atPath: root.path) {
                throw LocalActivityError.unreadableSource
            }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      (values.contentModificationDate ?? .distantPast) >= cutoff else { continue }
                urls.append(url)
            }
        }
        return urls
    }

    private func readEvents(from urls: [URL], cutoff: Date) async throws -> (events: [Event], summarizedLargeFiles: Int) {
        guard !urls.isEmpty else { return ([], 0) }
        var recordsBySession: [String: [CumulativeRecord]] = [:]
        var currentModelBySession: [String: String] = [:]
        var partialSessions = Set<String>()
        var matchesFound = 0
        var decodedRecords = 0
        let contextMarker = Data("\"type\":\"turn_context\"".utf8)
        let tokenMarker = Data("\"type\":\"token_count\"".utf8)
        let sizedURLs = urls.map { url in
            (url, (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let regularURLs = sizedURLs.filter { $0.1 <= largeFileThresholdBytes }.map(\.0)
        let largeURLs = sizedURLs.filter { $0.1 > largeFileThresholdBytes }

        func ingest(_ data: Data, sessionID: String) {
            for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: true) where rawLine.count <= 5_000_000 {
                matchesFound += 1
                guard let record = decodeCandidate(Data(rawLine)) else { continue }
                decodedRecords += 1
                switch record {
                case .model(let model):
                    currentModelBySession[sessionID] = model
                case .usage(let date, let total):
                    recordsBySession[sessionID, default: []].append(
                        CumulativeRecord(date: date, total: total, model: currentModelBySession[sessionID])
                    )
                }
            }
        }

        for url in regularURLs {
            try Task.checkCancellation()
            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: url)
            } catch {
                throw LocalActivityError.unreadableSource
            }
            let data: Data
            do {
                data = try handle.readToEnd() ?? Data()
                try handle.close()
            } catch {
                try? handle.close()
                throw LocalActivityError.unreadableSource
            }
            try Task.checkCancellation()
            let filtered = data.split(separator: 0x0A, omittingEmptySubsequences: true).filter { line in
                line.range(of: contextMarker) != nil || line.range(of: tokenMarker) != nil
            }
            ingest(
                Data(filtered.joined(separator: [0x0A])),
                sessionID: url.deletingPathExtension().lastPathComponent
            )
        }

        for (url, size) in largeURLs {
            try Task.checkCancellation()
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let offset = UInt64(max(0, size - largeFileTailBytes))
            try handle.seek(toOffset: offset)
            var data = try handle.readToEnd() ?? Data()
            if offset > 0, let newline = data.firstIndex(of: 0x0A) {
                data = Data(data[data.index(after: newline)...])
            }
            let sessionID = url.deletingPathExtension().lastPathComponent
            if offset > 0 || sessionStartDate(for: url).map({ $0 < cutoff }) ?? true {
                partialSessions.insert(sessionID)
            }
            let filtered = data.split(separator: 0x0A, omittingEmptySubsequences: true).filter { line in
                line.range(of: contextMarker) != nil || line.range(of: tokenMarker) != nil
            }
            ingest(Data(filtered.joined(separator: [0x0A])), sessionID: sessionID)
        }
        if matchesFound > 0, decodedRecords == 0 { throw LocalActivityError.unsupportedRecords }

        var output: [Event] = []
        for (sessionID, records) in recordsBySession {
            var previous: TokenUsage?
            var generation = 0
            for record in records.sorted(by: { $0.date < $1.date }) {
                let delta: TokenUsage
                if let previous {
                    if record.total == previous { continue }
                    if record.total.isAtLeast(previous) {
                        delta = .delta(from: previous, to: record.total)
                    } else {
                        generation += 1
                        delta = record.total
                    }
                } else {
                    if partialSessions.contains(sessionID) {
                        previous = record.total
                        continue
                    }
                    delta = record.total
                }
                previous = record.total
                guard delta.totalTokens > 0 else { continue }
                output.append(Event(
                    date: record.date,
                    usage: delta,
                    model: record.model ?? "unknown",
                    fingerprint: "\(sessionID):\(generation):\(record.total.fingerprint)"
                ))
            }
        }
        return (output, largeURLs.count)
    }

    private func sessionStartDate(for url: URL) -> Date? {
        let components = url.pathComponents
        guard components.count >= 4,
              let year = Int(components[components.count - 4]),
              let month = Int(components[components.count - 3]),
              let day = Int(components[components.count - 2]) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private enum Candidate { case model(String), usage(Date, TokenUsage) }

    private func decodeCandidate(_ data: Data) -> Candidate? {
        if let context = try? JSONDecoder().decode(TurnContextRecord.self, from: data),
           context.type == "turn_context" {
            let model = context.payload.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty, model.utf8.count <= 128,
                  model.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
            return .model(model)
        }
        guard let record = try? JSONDecoder().decode(TokenRecord.self, from: data), record.type == "event_msg",
              record.payload.type == "token_count", let info = record.payload.info,
              let total = info.totalTokenUsage?.validated, let date = parseDate(record.timestamp) else { return nil }
        return .usage(date, total)
    }

    private func parseDate(_ value: String) -> Date? {
        (try? fractionalISO.parse(value)) ?? (try? standardISO.parse(value))
    }
}

private struct TurnContextRecord: Decodable {
    let type: String
    let payload: Payload
    struct Payload: Decodable { let model: String }
}

private struct TokenRecord: Decodable {
    let timestamp: String
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let type: String
        let info: Info?
    }

    struct Info: Decodable {
        let lastTokenUsage: RawUsage?
        let totalTokenUsage: RawUsage?
        let modelContextWindow: Int64?

        enum CodingKeys: String, CodingKey {
            case lastTokenUsage = "last_token_usage"
            case totalTokenUsage = "total_token_usage"
            case modelContextWindow = "model_context_window"
        }
    }

    struct RawUsage: Decodable {
        let inputTokens: Int64
        let cachedInputTokens: Int64
        let outputTokens: Int64
        let totalTokens: Int64

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
        }

        var validated: TokenUsage? {
            guard inputTokens >= 0, cachedInputTokens >= 0, outputTokens >= 0, totalTokens >= 0,
                  cachedInputTokens <= inputTokens else { return nil }
            return TokenUsage(
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens,
                totalTokens: totalTokens
            )
        }
    }
}
