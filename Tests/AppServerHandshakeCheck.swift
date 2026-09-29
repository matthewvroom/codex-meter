import Foundation
#if canImport(CodexMeterCore)
import CodexMeterCore
#endif

@main
struct AppServerHandshakeCheck {
    static func main() async throws {
        if CommandLine.arguments.dropFirst().first == "app-server" {
            try runFakeServer()
            return
        }

        let candidates = CodexAppServerClient.executableCandidatePaths(
            home: "/Users/tester",
            environment: ["CODEX_PATH": "/custom/codex"]
        )
        precondition(candidates.prefix(5).elementsEqual([
            "/custom/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex"
        ]))

        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-meter-missing-\(UUID().uuidString)").path
        let missingClient = CodexAppServerClient(candidatePaths: [missingPath])
        do {
            _ = try await missingClient.readRateLimits()
            preconditionFailure("Expected the missing-executable error")
        } catch let error as CodexClientError {
            precondition(error == .executableNotFound)
            precondition(error.errorDescription == "Codex is not installed in a supported location.")
        }

        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: CommandLine.arguments[0])
        )
        let payload = try await client.readRateLimits()
        precondition(payload.snapshot.limitID == "codex")
        precondition(payload.snapshot.secondary?.remainingPercent == 56)
        await client.stop()

        let retryMarker = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-meter-retry-\(UUID().uuidString)")
        setenv("CODEX_METER_TEST_FAIL_FIRST_PATH", retryMarker.path, 1)
        let retryingClient = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: CommandLine.arguments[0]),
            responseTimeout: .seconds(1),
            connectionEndDelay: .milliseconds(300)
        )
        let retriedPayload = try await retryingClient.readRateLimits()
        precondition(retriedPayload.snapshot.secondary?.remainingPercent == 56)
        await retryingClient.stop()
        unsetenv("CODEX_METER_TEST_FAIL_FIRST_PATH")
        try? FileManager.default.removeItem(at: retryMarker)

        let initializationMarker = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-meter-initialize-retry-\(UUID().uuidString)")
        setenv("CODEX_METER_TEST_HANG_INITIALIZE_PATH", initializationMarker.path, 1)
        let initializingClient = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: CommandLine.arguments[0])
        )
        let initializedPayload = try await initializingClient.readRateLimits()
        precondition(initializedPayload.snapshot.secondary?.remainingPercent == 56)
        await initializingClient.stop()
        unsetenv("CODEX_METER_TEST_HANG_INITIALIZE_PATH")
        try? FileManager.default.removeItem(at: initializationMarker)
        print("Deterministic app-server initialization handshake passed")
    }

    private static func runFakeServer() throws {
        var step = 0
        var shouldHang = false
        if let marker = ProcessInfo.processInfo.environment["CODEX_METER_TEST_FAIL_FIRST_PATH"],
           !FileManager.default.fileExists(atPath: marker) {
            FileManager.default.createFile(atPath: marker, contents: Data())
            shouldHang = true
        }
        var shouldHangInitialization = false
        if let marker = ProcessInfo.processInfo.environment["CODEX_METER_TEST_HANG_INITIALIZE_PATH"],
           !FileManager.default.fileExists(atPath: marker) {
            FileManager.default.createFile(atPath: marker, contents: Data())
            shouldHangInitialization = true
        }
        while let line = readLine() {
            let data = Data(line.utf8)
            guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = message["method"] as? String else { exit(20) }
            switch (step, method) {
            case (0, "initialize"):
                if shouldHangInitialization {
                    Thread.sleep(forTimeInterval: 6)
                    return
                }
                guard let id = message["id"] else { exit(21) }
                write(["id": id, "result": [:]])
                step = 1
            case (1, "initialized"):
                step = 2
            case (2, "account/rateLimits/read"):
                if shouldHang {
                    Thread.sleep(forTimeInterval: 3)
                    return
                }
                if ProcessInfo.processInfo.environment["CODEX_METER_TEST_FAIL_FIRST_PATH"] != nil {
                    Thread.sleep(forTimeInterval: 0.5)
                }
                guard let id = message["id"] else { exit(22) }
                write([
                    "id": id,
                    "result": [
                        "rateLimitsByLimitId": [
                            "codex": [
                                "limitId": "codex",
                                "planType": "prolite",
                                "secondary": [
                                    "usedPercent": 44,
                                    "windowDurationMins": 10_080,
                                    "resetsAt": 2_000_000_000
                                ]
                            ]
                        ]
                    ]
                ])
                return
            default:
                exit(23)
            }
        }
        exit(24)
    }

    private static func write(_ object: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
