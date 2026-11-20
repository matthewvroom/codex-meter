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
        case .timedOut: return "This Mac activity scan took too long. Select Refresh to continue from the last completed log."
        }
    }
}

public struct HourlyTokenUsage: Codable, Equatable, Identifiable, Sendable {
    /// Start of the local hour, or of the remaining part of an hour after a clock change.
    public let date: Date
    public let usage: TokenUsage
    public var id: Date { date }

    public init(date: Date, usage: TokenUsage) {
        self.date = date
        self.usage = usage
    }
}

public struct DailyTokenUsage: Codable, Equatable, Identifiable, Sendable {
    public let date: Date
    public let usage: TokenUsage
    /// Recorded usage by hour. Nil when the scan did not request hourly detail.
    public let hours: [HourlyTokenUsage]?
    public var id: Date { date }

    public init(date: Date, usage: TokenUsage, hours: [HourlyTokenUsage]? = nil) {
        self.date = date
        self.usage = usage
        self.hours = hours
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

    private struct FileVersion: Equatable {
        let size: Int
        let modifiedAt: Date
        let attributesModifiedAt: Date?
        let identifier: NSObject?
    }

    private struct LogFile {
        let url: URL
        let version: FileVersion
    }

    private struct ParsedLog {
        let version: FileVersion
        var records: [CumulativeRecord] = []
        var lastModel: String?
        var hadCandidates = false
        var decodedRecords = false
    }

    private var cachedLogs: [URL: ParsedLog] = [:]
    private let roots: [URL]
    private let calendar: Calendar
    private let largeFileThresholdBytes: Int
    private let largeFileTailBytes: Int
    private let fractionalISO = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private let standardISO = Date.ISO8601FormatStyle()
    private let contextMarker = Data("\"type\":\"turn_context\"".utf8)
    private let tokenMarker = Data("\"type\":\"token_count\"".utf8)

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

    public func scan(
        days dayCount: Int = 7, now: Date = Date(), includeHourlyUsage: Bool = false
    ) async throws -> LocalActivitySnapshot {
        let days = max(1, min(90, dayCount))
        let startToday = calendar.startOfDay(for: now)
        let firstDate = calendar.date(byAdding: .day, value: -(days - 1), to: startToday) ?? startToday
        let cutoff = calendar.startOfDay(for: firstDate)
        let candidates = try discoverFiles(modifiedSince: calendar.date(byAdding: .day, value: -1, to: cutoff) ?? cutoff)
        let candidateURLs = Set(candidates.map(\.url))
        cachedLogs = cachedLogs.filter { candidateURLs.contains($0.key) }
        let result = try readEvents(from: candidates, cutoff: cutoff)

        var seen = Set<String>()
        var buckets: [Date: TokenUsage] = [:]
        var hourlyBuckets: [Date: [Date: TokenUsage]] = [:]
        var modelBuckets: [String: TokenUsage] = [:]
        for event in result.events where event.date >= cutoff && event.date <= now {
            try Task.checkCancellation()
            guard seen.insert(event.fingerprint).inserted else { continue }
            let day = calendar.startOfDay(for: event.date)
            buckets[day] = (buckets[day] ?? TokenUsage()) + event.usage
            if includeHourlyUsage {
                let hour = hourStart(containing: event.date, dayStart: day)
                hourlyBuckets[day, default: [:]][hour] =
                    (hourlyBuckets[day]?[hour] ?? TokenUsage()) + event.usage
            }
            modelBuckets[event.model] = (modelBuckets[event.model] ?? TokenUsage()) + event.usage
        }

        let output = (0..<days).compactMap { offset -> DailyTokenUsage? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: cutoff) else { return nil }
            let date = calendar.startOfDay(for: day)
            let hours = includeHourlyUsage
                ? hourlyBuckets[date, default: [:]].sorted { $0.key < $1.key }.map {
                    HourlyTokenUsage(date: $0.key, usage: $0.value)
                }
                : nil
            return DailyTokenUsage(date: date, usage: buckets[date] ?? TokenUsage(), hours: hours)
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
            filesRead: result.filesRead,
            summarizedLargeFiles: result.summarizedLargeFiles
        )
    }

    private func hourStart(containing date: Date, dayStart: Date) -> Date {
        let hour = max(dayStart, calendar.dateInterval(of: .hour, for: date)?.start ?? dayStart)
        let zone = calendar.timeZone
        // For fractional-hour clock changes, the calendar's hour can start before
        // the clock moved. Assign the new offset its own bucket at the transition.
        if zone.secondsFromGMT(for: hour) != zone.secondsFromGMT(for: date),
           let transition = zone.nextDaylightSavingTimeTransition(after: hour),
           transition <= date {
            return transition
        }
        return hour
    }

    private func discoverFiles(modifiedSince cutoff: Date) throws -> [LogFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            .attributeModificationDateKey, .fileResourceIdentifierKey
        ]
        var files: [LogFile] = []
        for root in roots {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: root.path), !FileManager.default.isReadableFile(atPath: root.path) {
                throw LocalActivityError.unreadableSource
            }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            var rootFiles: [LogFile] = []
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let size = values.fileSize,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt >= cutoff else { continue }
                rootFiles.append(LogFile(url: url, version: FileVersion(
                    size: size,
                    modifiedAt: modifiedAt,
                    attributesModifiedAt: values.attributeModificationDate,
                    identifier: values.fileResourceIdentifier as? NSObject
                )))
            }
            files.append(contentsOf: rootFiles.sorted { $0.url.path < $1.url.path })
        }
        return files
    }

    private func readEvents(from files: [LogFile], cutoff: Date) throws
        -> (events: [Event], filesRead: Int, summarizedLargeFiles: Int) {
        var recordsBySession: [String: [CumulativeRecord]] = [:]
        var currentModelBySession: [String: String] = [:]
        var firstCompleteRecordDates: [String: Date] = [:]
        var filesRead = 0
        var hadCandidates = false
        var decodedRecords = false
        let regularFiles = files.filter { $0.version.size <= largeFileThresholdBytes }
        let largeFiles = files.filter { $0.version.size > largeFileThresholdBytes }

        for file in regularFiles + largeFiles {
            try Task.checkCancellation()
            let isLarge = file.version.size > largeFileThresholdBytes
            let offset = isLarge ? max(0, file.version.size - largeFileTailBytes) : 0
            let parsed: ParsedLog
            if let cached = cachedLogs[file.url], cached.version == file.version {
                parsed = cached
            } else {
                parsed = try parseLog(file, from: offset)
                // Keep each completed log even if the rest of this scan is canceled.
                cachedLogs[file.url] = parsed
                filesRead += 1
            }
            hadCandidates = hadCandidates || parsed.hadCandidates
            decodedRecords = decodedRecords || parsed.decodedRecords

            let sessionID = file.url.deletingPathExtension().lastPathComponent
            let isPartial: Bool
            if !isLarge {
                isPartial = false
            } else if offset > 0 {
                isPartial = true
            } else if let startedAt = sessionStartDate(for: file.url) {
                isPartial = startedAt < cutoff
            } else {
                isPartial = true
            }
            if !isPartial, let earliest = parsed.records.min(by: { $0.date < $1.date })?.date {
                firstCompleteRecordDates[sessionID] = min(firstCompleteRecordDates[sessionID] ?? earliest, earliest)
            }
            if !parsed.records.isEmpty {
                if let previousModel = currentModelBySession[sessionID], parsed.records.first?.model == nil {
                    recordsBySession[sessionID, default: []].append(contentsOf: parsed.records.map {
                        CumulativeRecord(date: $0.date, total: $0.total, model: $0.model ?? previousModel)
                    })
                } else {
                    recordsBySession[sessionID, default: []].append(contentsOf: parsed.records)
                }
            }
            if let model = parsed.lastModel {
                currentModelBySession[sessionID] = model
            }
        }
        if hadCandidates, !decodedRecords { throw LocalActivityError.unsupportedRecords }

        var output: [Event] = []
        for (sessionID, records) in recordsBySession {
            try Task.checkCancellation()
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
                    // A truncated copy cannot invalidate the first record of a complete copy.
                    if (firstCompleteRecordDates[sessionID] ?? .distantFuture) > record.date {
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
        return (output, filesRead, largeFiles.count)
    }

    private func parseLog(_ file: LogFile, from offset: Int) throws -> ParsedLog {
        let length = file.version.size - offset
        guard length > 0 else { return ParsedLog(version: file.version) }

        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: file.url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            data = try handle.read(upToCount: length) ?? Data()
        } catch {
            throw LocalActivityError.unreadableSource
        }
        // A log that grew during the read is picked up by its next version.
        guard data.count == length else { throw LocalActivityError.unreadableSource }
        let decoded = try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var parsed = (
                records: [CumulativeRecord](),
                lastModel: String?.none,
                hadCandidates: false,
                decodedRecords: false
            )
            guard let base = bytes.baseAddress else { return parsed }
            var start = 0
            var nextCancellationCheck = 0
            while start < bytes.count {
                if start >= nextCancellationCheck {
                    try Task.checkCancellation()
                    nextCancellationCheck = start + 256 * 1_024
                }
                let line = base.advanced(by: start)
                let end = memchr(line, 0x0A, bytes.count - start).map {
                    start + line.distance(to: UnsafeRawPointer($0))
                } ?? bytes.count
                defer { start = end + 1 }

                // A tail may start inside a record. Drop that first line.
                guard (offset == 0 || start > 0), end > start, end - start <= 5_000_000 else { continue }
                let range = start..<end
                guard data.range(of: contextMarker, in: range) != nil
                        || data.range(of: tokenMarker, in: range) != nil else { continue }
                parsed.hadCandidates = true
                guard let record = decodeCandidate(data[range]) else { continue }
                parsed.decodedRecords = true
                switch record {
                case .model(let model):
                    parsed.lastModel = model
                case .usage(let date, let total):
                    parsed.records.append(CumulativeRecord(date: date, total: total, model: parsed.lastModel))
                }
            }
            return parsed
        }
        return ParsedLog(
            version: file.version,
            records: decoded.records,
            lastModel: decoded.lastModel,
            hadCandidates: decoded.hadCandidates,
            decodedRecords: decoded.decodedRecords
        )
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
