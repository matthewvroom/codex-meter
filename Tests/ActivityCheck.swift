import Foundation
#if canImport(CodexMeterCore)
import CodexMeterCore
#endif

@main
struct ActivityCheck {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let active = root.appendingPathComponent("active", isDirectory: true)
        let archived = root.appendingPathComponent("archived", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let now = Date()
        func context(_ model: String) -> String {
            #"{"timestamp":"\#(formatter.string(from: now))","type":"turn_context","payload":{"model":"\#(model)","summary":"never retain me"}}"#
        }
        func event(at offset: TimeInterval, input: Int, cached: Int, output: Int, total: Int) -> String {
            let timestamp = formatter.string(from: now.addingTimeInterval(offset))
            return #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2},"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(total)},"model_context_window":1000},"private_prompt":"never retain me"}}"#
        }
        let records = [
            context("gpt-5.6-sol"),
            event(at: -4, input: 100, cached: 40, output: 20, total: 120),
            event(at: -3, input: 100, cached: 40, output: 20, total: 120),
            context("gpt-5.6-luna"),
            event(at: -2, input: 150, cached: 50, output: 30, total: 180),
            event(at: -1, input: 30, cached: 5, output: 10, total: 40),
            #"{"timestamp":"\#(formatter.string(from: now))","type":"event_msg","payload":{"type":"user_message","message":"secret"}}"#
        ].joined(separator: "\n") + "\n"
        let name = "rollout-2026-session-abc.jsonl"
        let activeLog = active.appendingPathComponent(name)
        let archivedLog = archived.appendingPathComponent(name)
        try Data(records.utf8).write(to: activeLog)
        try Data(records.utf8).write(to: archivedLog)

        let scanner = LocalActivityScanner(roots: [active, archived])
        let snapshot = try await scanner.scan(days: 7)
        precondition(snapshot.filesRead == 2)
        precondition(snapshot.days.count == 7)
        precondition(snapshot.total.inputTokens == 180)
        precondition(snapshot.total.cachedInputTokens == 55)
        precondition(snapshot.total.outputTokens == 40)
        precondition(snapshot.total.totalTokens == 220)
        precondition(snapshot.models.count == 2)
        precondition(snapshot.models.first(where: { $0.model == "gpt-5.6-sol" })?.usage.totalTokens == 120)
        precondition(snapshot.models.first(where: { $0.model == "gpt-5.6-luna" })?.usage.totalTokens == 100)

        let unchanged = try await scanner.scan(days: 7)
        precondition(unchanged.filesRead == 0)
        precondition(unchanged.total == snapshot.total)

        let hourly = try await scanner.scan(days: 7, includeHourlyUsage: true)
        precondition(hourly.filesRead == 0)
        precondition(hourly.total == snapshot.total)
        for day in hourly.days {
            guard let hours = day.hours else { preconditionFailure("Missing opted-in hourly data") }
            precondition(hours.reduce(TokenUsage()) { $0 + $1.usage } == day.usage)
        }
        precondition(hourly.days.contains { $0.hours == [] })
        let encoded = try JSONEncoder().encode(snapshot)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let encodedDays = json?["days"] as? [[String: Any]]
        precondition(encodedDays?.allSatisfy { $0["hours"] == nil } == true)
        let decoded = try JSONDecoder().decode(LocalActivitySnapshot.self, from: encoded)
        precondition(decoded.days.allSatisfy { $0.hours == nil })

        let appended = try FileHandle(forWritingTo: activeLog)
        try appended.seekToEnd()
        try appended.write(contentsOf: Data((event(at: 0, input: 40, cached: 5, output: 10, total: 50) + "\n").utf8))
        try appended.close()
        let changed = try await scanner.scan(days: 7)
        precondition(changed.filesRead == 1)
        precondition(changed.total.totalTokens == 230)

        try FileManager.default.removeItem(at: activeLog)
        let removed = try await scanner.scan(days: 7)
        precondition(removed.filesRead == 0)
        precondition(removed.total == snapshot.total)

        // Restore the original timestamp after replacing the file with equally sized contents.
        let sameSizeReplacement = records.replacingOccurrences(of: "\"model\":\"gpt-5.6-luna\"", with: "\"model\":\"gpt-5.6-test\"")
        precondition(sameSizeReplacement.utf8.count == records.utf8.count)
        let archivedModifiedAt = try archivedLog.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        try Data(sameSizeReplacement.utf8).write(to: archivedLog, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: archivedModifiedAt], ofItemAtPath: archivedLog.path)
        let replaced = try await scanner.scan(days: 7)
        precondition(replaced.filesRead == 1)
        precondition(replaced.total == snapshot.total)
        precondition(replaced.models.first(where: { $0.model == "gpt-5.6-test" })?.usage.totalTokens == 100)

        let rates = LocalCostRates(inputPerMillion: 2, cachedInputPerMillion: 0.5, outputPerMillion: 8)
        let expected = 125.0 / 1_000_000 * 2 + 55.0 / 1_000_000 * 0.5 + 40.0 / 1_000_000 * 8
        precondition(abs(rates.estimate(snapshot.total) - expected) < 0.0000001)
        precondition(OpenAIPriceCatalog.price(for: "gpt-5.6-sol")?.inputPerMillion == 4)
        precondition(OpenAIPriceCatalog.price(for: "gpt-5.6-terra")?.outputPerMillion == 12)
        precondition(OpenAIPriceCatalog.price(for: "gpt-5.6-luna")?.cachedInputPerMillion == 0.02)
        precondition(OpenAIPriceCatalog.price(for: "not-a-real-model") == nil)
        let official = OpenAIPriceCatalog.estimate(snapshot.models)
        precondition(official > 0)
        precondition(DisplayCurrency.usd.convertFromUSD(10) == 10)
        precondition(abs(DisplayCurrency.eur.convertFromUSD(1) - (1 / 1.1405)) < 0.0000001)
        precondition(abs(DisplayCurrency.aud.convertFromUSD(1) - (1.6428 / 1.1405)) < 0.0000001)

        let dateParts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let largeRoot = root
            .appendingPathComponent(String(dateParts.year!), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", dateParts.month!), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", dateParts.day!), isDirectory: true)
        try FileManager.default.createDirectory(at: largeRoot, withIntermediateDirectories: true)
        try Data(records.utf8).write(to: largeRoot.appendingPathComponent("rollout-large.jsonl"))
        let summarized = try await LocalActivityScanner(
            roots: [largeRoot],
            largeFileThresholdBytes: 1,
            largeFileTailBytes: 1_024 * 1_024
        ).scan(days: 7)
        precondition(summarized.summarizedLargeFiles == 1)
        precondition(summarized.total.totalTokens == 220)

        let truncatedRoot = largeRoot.appendingPathComponent("truncated", isDirectory: true)
        try FileManager.default.createDirectory(at: truncatedRoot, withIntermediateDirectories: true)
        let inherited = event(at: -2, input: 1_000_000_000, cached: 900_000_000, output: 2_000_000, total: 1_002_000_000)
        let advanced = event(at: -1, input: 1_000_000_100, cached: 900_000_040, output: 2_000_020, total: 1_002_000_120)
        let truncatedRecords = String(repeating: "discarded filler line\n", count: 500)
            + context("gpt-5.6-terra") + "\n" + inherited + "\n" + advanced + "\n"
        try Data(truncatedRecords.utf8).write(to: truncatedRoot.appendingPathComponent("rollout-truncated.jsonl"))
        let truncated = try await LocalActivityScanner(
            roots: [truncatedRoot],
            largeFileThresholdBytes: 1,
            largeFileTailBytes: 4_096
        ).scan(days: 7, includeHourlyUsage: true)
        precondition(truncated.summarizedLargeFiles == 1)
        precondition(truncated.total.inputTokens == 100)
        precondition(truncated.total.cachedInputTokens == 40)
        precondition(truncated.total.outputTokens == 20)
        precondition(truncated.total.totalTokens == 120)
        precondition(truncated.days.flatMap { $0.hours ?? [] }.map(\.usage.totalTokens) == [120])

        let overlapScanner = LocalActivityScanner(
            roots: [active, archived],
            largeFileThresholdBytes: 4_096,
            largeFileTailBytes: 4_096
        )
        try Data(records.utf8).write(to: activeLog)
        let paddedArchive = String(repeating: "discarded filler line\n", count: 300) + records
        try Data(paddedArchive.utf8).write(to: archivedLog)
        let overlap = try await overlapScanner.scan(days: 7)
        precondition(overlap.summarizedLargeFiles == 1)
        precondition(overlap.total == snapshot.total)
        precondition(overlap.models == snapshot.models)
        let cachedOverlap = try await overlapScanner.scan(days: 7)
        precondition(cachedOverlap.filesRead == 0)
        precondition(cachedOverlap.total == snapshot.total)

        let unknownRoot = root.appendingPathComponent("unknown", isDirectory: true)
        try FileManager.default.createDirectory(at: unknownRoot, withIntermediateDirectories: true)
        try Data((event(at: 0, input: 10, cached: 0, output: 2, total: 12) + "\n").utf8)
            .write(to: unknownRoot.appendingPathComponent("rollout-unknown.jsonl"))
        let unknown = try await LocalActivityScanner(roots: [unknownRoot]).scan(days: 1)
        precondition(unknown.models.first?.model == "unknown")

        let timezoneRoot = root.appendingPathComponent("timezone", isDirectory: true)
        try FileManager.default.createDirectory(at: timezoneRoot, withIntermediateDirectories: true)
        let sundayRecord = """
        {"timestamp":"2026-08-23T23:30:00-07:00","type":"turn_context","payload":{"model":"gpt-5.6-luna"}}
        {"timestamp":"2026-08-23T23:30:01-07:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":10},"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":10}}}}
        """
        let mondayRecord = """
        {"timestamp":"2026-08-24T00:30:00-07:00","type":"turn_context","payload":{"model":"gpt-5.6-luna"}}
        {"timestamp":"2026-08-24T00:30:01-07:00","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":20},"total_token_usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":20}}}}
        """
        try Data(sundayRecord.utf8).write(to: timezoneRoot.appendingPathComponent("rollout-sunday.jsonl"))
        try Data(mondayRecord.utf8).write(to: timezoneRoot.appendingPathComponent("rollout-monday.jsonl"))
        var pacificCalendar = Calendar(identifier: .gregorian)
        pacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let pacificNow = ISO8601DateFormatter().date(from: "2026-08-24T01:00:00-07:00")!
        let timezoneSnapshot = try await LocalActivityScanner(
            roots: [timezoneRoot],
            calendar: pacificCalendar
        ).scan(days: 2, now: pacificNow, includeHourlyUsage: true)
        precondition(timezoneSnapshot.days.count == 2)
        precondition(timezoneSnapshot.days[0].usage.totalTokens == 10)
        precondition(timezoneSnapshot.days[1].usage.totalTokens == 20)
        precondition(pacificCalendar.component(.weekday, from: timezoneSnapshot.days[0].date) == 1)
        precondition(pacificCalendar.component(.weekday, from: timezoneSnapshot.days[1].date) == 2)
        precondition(timezoneSnapshot.days[0].hours?.map(\.date) == [formatter.date(from: "2026-08-23T23:00:00-07:00")!])
        precondition(timezoneSnapshot.days[1].hours?.map(\.date) == [formatter.date(from: "2026-08-24T00:00:00-07:00")!])

        let fallBackRoot = root.appendingPathComponent("fall-back", isDirectory: true)
        try FileManager.default.createDirectory(at: fallBackRoot, withIntermediateDirectories: true)
        func hourlyEvent(_ timestamp: String, _ total: Int) -> String {
            #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(total),"cached_input_tokens":0,"output_tokens":0,"total_tokens":\#(total)}}}}"#
        }
        let fallBackRecords = [
            hourlyEvent("2026-11-01T01:05:00-07:00", 10),
            hourlyEvent("2026-11-01T01:45:00-07:00", 15),
            hourlyEvent("2026-11-01T01:15:00-08:00", 35),
            hourlyEvent("2026-11-01T02:00:00-08:00", 99)
        ].joined(separator: "\n") + "\n"
        try Data(fallBackRecords.utf8).write(to: fallBackRoot.appendingPathComponent("rollout-fall-back.jsonl"))
        let fallBack = try await LocalActivityScanner(roots: [fallBackRoot], calendar: pacificCalendar)
            .scan(days: 1, now: formatter.date(from: "2026-11-01T01:50:00-08:00")!, includeHourlyUsage: true)
        let expectedStarts = ["2026-11-01T01:00:00-07:00", "2026-11-01T01:00:00-08:00"]
            .map { formatter.date(from: $0)! }
        precondition(fallBack.days.first?.hours?.map(\.date) == expectedStarts)
        precondition(fallBack.days.first?.hours?.map(\.usage.totalTokens) == [15, 20])
        precondition(fallBack.total.totalTokens == 35)

        let halfHourRoot = root.appendingPathComponent("half-hour-shift", isDirectory: true)
        try FileManager.default.createDirectory(at: halfHourRoot, withIntermediateDirectories: true)
        let halfHourRecords = [
            hourlyEvent("2026-04-05T01:40:00+11:00", 10),
            hourlyEvent("2026-04-05T01:40:00+10:30", 25)
        ].joined(separator: "\n") + "\n"
        try Data(halfHourRecords.utf8).write(to: halfHourRoot.appendingPathComponent("rollout-half-hour.jsonl"))
        var lordHoweCalendar = Calendar(identifier: .gregorian)
        lordHoweCalendar.timeZone = TimeZone(identifier: "Australia/Lord_Howe")!
        let halfHour = try await LocalActivityScanner(roots: [halfHourRoot], calendar: lordHoweCalendar)
            .scan(days: 1, now: formatter.date(from: "2026-04-05T03:00:00+10:30")!, includeHourlyUsage: true)
        let halfHourStarts = ["2026-04-05T01:00:00+11:00", "2026-04-05T01:30:00+10:30"]
            .map { formatter.date(from: $0)! }
        precondition(halfHour.days.first?.hours?.map(\.date) == halfHourStarts)
        precondition(halfHour.days.first?.hours?.map(\.usage.totalTokens) == [10, 15])

        let invalidRoot = root.appendingPathComponent("invalid", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
        let invalidLog = invalidRoot.appendingPathComponent("rollout-invalid.jsonl")
        try Data("ignored record\n".utf8).write(to: invalidRoot.appendingPathComponent("rollout-ignored.jsonl"))
        try Data(#"{"type":"token_count","private":"do not echo"}"#.utf8)
            .write(to: invalidLog)
        let retryingScanner = LocalActivityScanner(roots: [invalidRoot])
        do {
            _ = try await retryingScanner.scan(days: 7)
            preconditionFailure("Unsupported records must fail visibly")
        } catch LocalActivityError.unsupportedRecords {
            // Expected: the source line is never included in the error.
        }
        try Data(records.utf8).write(to: invalidLog)
        let retried = try await retryingScanner.scan(days: 7)
        precondition(retried.filesRead == 1)
        precondition(retried.total == snapshot.total)
        print("Local activity checks passed")
    }
}
