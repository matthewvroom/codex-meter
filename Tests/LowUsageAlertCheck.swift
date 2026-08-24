import Foundation
#if canImport(CodexMeterCore)
import CodexMeterCore
#endif

@main
struct LowUsageAlertCheck {
    static func main() {
        var state = LowUsageAlertState()
        precondition(state.observe(windowID: "weekly-a", remainingPercent: 19, threshold: 20))
        precondition(!state.observe(windowID: "weekly-a", remainingPercent: 18, threshold: 20))
        precondition(!state.observe(windowID: "weekly-a", remainingPercent: 30, threshold: 20))
        precondition(state.observe(windowID: "weekly-a", remainingPercent: 20, threshold: 20))
        precondition(!state.observe(windowID: "weekly-a", remainingPercent: 19, threshold: 20))
        precondition(state.observe(windowID: "weekly-b", remainingPercent: 10, threshold: 20))
        precondition(!state.observe(windowID: "weekly-b", remainingPercent: 9, threshold: 20))
        precondition(state.observe(windowID: "weekly-b", remainingPercent: 24, threshold: 25))

        let encoded = try! JSONEncoder().encode(state)
        precondition(try! JSONDecoder().decode(LowUsageAlertState.self, from: encoded) == state)
        print("Low-usage alert checks passed")
    }
}
