import Foundation

@main
enum WeeklyResetHistoryCheck {
    static func main() throws {
        let scheduledReset = Date(timeIntervalSince1970: 2_000_000_000)
        let week: TimeInterval = 7 * 24 * 60 * 60

        func reading(
            at offset: TimeInterval,
            nextReset: TimeInterval,
            used: Int,
            accountID: String? = "account-a",
            plan: String = "pro",
            banked: Int? = nil,
            durationMinutes: Int = 10_080
        ) -> RateLimitPayload {
            RateLimitPayload(
                snapshot: RateLimitSnapshot(
                    limitID: "codex",
                    limitName: nil,
                    planType: plan,
                    primary: RateLimitWindow(usedPercent: 10, resetsAt: nil, durationMinutes: 300),
                    secondary: RateLimitWindow(
                        usedPercent: used,
                        resetsAt: scheduledReset.addingTimeInterval(nextReset),
                        durationMinutes: durationMinutes
                    )
                ),
                fetchedAt: scheduledReset.addingTimeInterval(offset),
                availableResetCredits: banked,
                accountID: accountID
            )
        }

        var history = WeeklyResetHistory()
        history.observe(reading(at: -120, nextReset: 0, used: 85))
        precondition(history.resetDates.isEmpty, "An initial read cannot establish a reset")
        let data = try JSONEncoder().encode(history)
        history = try JSONDecoder().decode(WeeklyResetHistory.self, from: data)
        history.observe(reading(at: 30, nextReset: 0, used: 85))
        history.observe(reading(at: 60, nextReset: week, used: 3))
        precondition(history.resetDates == [scheduledReset], "Record the earlier observed deadline, even across relaunch")
        history.observe(reading(at: 120, nextReset: week, used: 4))
        history.observe(reading(at: 90, nextReset: 2 * week, used: 1, accountID: "account-b"))
        precondition(history.resetDates == [scheduledReset], "Repeated and out-of-order reads cannot change history")
        history.observe(reading(at: 180, nextReset: week, used: 5, accountID: nil))
        precondition(history.resetDates == [scheduledReset], "An omitted identifier does not clear confirmed history")
        history.observe(reading(at: 240, nextReset: 2 * week, used: 1, accountID: "account-b"))
        precondition(history.resetDates.isEmpty, "A known account switch must clear this profile’s history")

        var early = WeeklyResetHistory()
        early.observe(reading(at: -7_200, nextReset: 0, used: 72))
        early.observe(reading(at: -3_600, nextReset: week - 5_400, used: 3))
        precondition(early.resetDates == [scheduledReset.addingTimeInterval(-5_400)], "Record the observed early window restart")

        var creditExpired = WeeklyResetHistory()
        creditExpired.observe(reading(at: -7_200, nextReset: 0, used: 72, banked: 1))
        creditExpired.observe(reading(at: -3_600, nextReset: 0, used: 72, banked: 0))
        precondition(creditExpired.resetDates.isEmpty, "A drop in banked credits does not prove a reset")

        var ambiguous = WeeklyResetHistory()
        ambiguous.observe(reading(at: -7_200, nextReset: 0, used: 72))
        ambiguous.observe(reading(at: -3_600, nextReset: week - 8_000, used: 3))
        precondition(ambiguous.resetDates.isEmpty, "A window that started outside the observation interval cannot confirm an early reset")

        var futureWindow = WeeklyResetHistory()
        futureWindow.observe(reading(at: -120, nextReset: 0, used: 85))
        futureWindow.observe(reading(at: 60, nextReset: week + 3_600, used: 3))
        precondition(futureWindow.resetDates.isEmpty, "A window with a future start does not establish a completed reset")

        var afterPlanChange = WeeklyResetHistory()
        afterPlanChange.observe(reading(at: -120, nextReset: 0, used: 85))
        afterPlanChange.observe(reading(at: 60, nextReset: week, used: 3, plan: "plus"))
        precondition(afterPlanChange.resetDates.isEmpty)

        var offline = WeeklyResetHistory()
        offline.observe(reading(at: -week, nextReset: 0, used: 85))
        offline.observe(reading(at: 60, nextReset: week, used: 3))
        precondition(offline.resetDates.isEmpty, "A gap of one window or longer cannot prove a reset")

        var monthly = WeeklyResetHistory()
        monthly.observe(reading(at: -120, nextReset: 0, used: 85, durationMinutes: 43_200))
        monthly.observe(reading(at: 60, nextReset: 30 * 86_400, used: 3, durationMinutes: 43_200))
        precondition(monthly.resetDates.isEmpty, "Monthly windows do not produce weekly reset markers")

        early.observe(reading(at: week + 86_400, nextReset: 2 * week, used: 4))
        precondition(early.resetDates.isEmpty, "History is pruned after eight days")
        print("Weekly reset history checks passed")
    }
}
