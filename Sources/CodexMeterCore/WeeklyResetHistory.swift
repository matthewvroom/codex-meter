import Foundation

public struct WeeklyResetHistory: Codable, Equatable, Sendable {
    private struct Observation: Codable, Equatable, Sendable {
        let fetchedAt: Date
        let resetsAt: Date
        let durationMinutes: Int
        let usedPercent: Int
        let limitID: String?
        let planType: String?

        init?(_ payload: RateLimitPayload) {
            let snapshot = payload.snapshot
            guard let window = snapshot.windows.first(where: { $0.isWeekly && ($0.durationMinutes ?? 0) <= 8 * 24 * 60 }),
                  let durationMinutes = window.durationMinutes,
                  let resetsAt = window.resetsAt, resetsAt > payload.fetchedAt else { return nil }
            self.fetchedAt = payload.fetchedAt
            self.resetsAt = resetsAt
            self.durationMinutes = durationMinutes
            self.usedPercent = window.usedPercent
            self.limitID = snapshot.limitID
            self.planType = snapshot.planType
        }

        var duration: TimeInterval { TimeInterval(durationMinutes) * 60 }

        func resetDate(since previous: Self) -> Date? {
            guard limitID == previous.limitID,
                  planType == previous.planType,
                  durationMinutes == previous.durationMinutes,
                  fetchedAt.timeIntervalSince(previous.fetchedAt) < duration,
                  resetsAt > previous.resetsAt,
                  usedPercent < previous.usedPercent else { return nil }

            let windowStart = resetsAt.addingTimeInterval(-duration)
            guard windowStart <= fetchedAt else { return nil }
            if previous.resetsAt <= fetchedAt {
                // An early restart could invalidate the old deadline while Meter is closed.
                return windowStart >= previous.resetsAt ? previous.resetsAt : nil
            }
            // Only infer an early reset when the new window started between these reads.
            return windowStart > previous.fetchedAt ? windowStart : nil
        }
    }

    private static let retention: TimeInterval = 8 * 24 * 60 * 60
    private var accountID: String?
    private var observation: Observation?
    public private(set) var resetDates: [Date] = []

    public init() {}

    public mutating func observe(_ payload: RateLimitPayload) {
        if let observation, payload.fetchedAt <= observation.fetchedAt { return }

        let observedAccountID = payload.accountID.flatMap { $0.isEmpty ? nil : $0 }
        if let observedAccountID, observedAccountID != accountID {
            accountID = observedAccountID
            observation = nil
            resetDates.removeAll()
        }

        let cutoff = payload.fetchedAt.addingTimeInterval(-Self.retention)
        resetDates.removeAll { $0 < cutoff }

        // If a later response omits the known account ID, keep the last usable reading.
        guard observedAccountID == accountID, let current = Observation(payload) else { return }
        defer { observation = current }
        guard let observation, let reset = current.resetDate(since: observation),
              !resetDates.contains(reset) else { return }
        resetDates.append(reset)
    }
}
