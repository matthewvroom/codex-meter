import AppKit
import CodexMeterCore
import Foundation
import ServiceManagement
import UserNotifications

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconAndPercentage
    case resetAndPercentage = "resetAndPercentageNoPace"
    case resetPercentageAndPace = "resetAndPercentage"
    case percentage
    case icon
    case activity

    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconAndPercentage: return "Icon + Percentage"
        case .resetAndPercentage: return "Reset + Percentage"
        case .resetPercentageAndPace: return "Reset + Percentage + Pace"
        case .percentage: return "Percentage Only"
        case .icon: return "Icon Only"
        case .activity: return "Activity Chart"
        }
    }
}

struct AccountProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let homePath: String?
    var email: String?

    var homeURL: URL? { homePath.map(URL.init(fileURLWithPath:)) }
    var displayName: String { email ?? name }
}

struct Celebration: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
}

@MainActor
final class UsageStore: ObservableObject {
    private static let defaultAccountID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    @Published private(set) var payload: RateLimitPayload?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var accountErrorMessage: String?
    @Published private(set) var activity: LocalActivitySnapshot?
    @Published private(set) var activityError: String?
    @Published private(set) var isActivityRefreshing = false
    @Published var alertThreshold: Int {
        didSet { UserDefaults.standard.set(alertThreshold, forKey: Self.thresholdKey) }
    }
    @Published private(set) var launchAtLogin = false
    @Published var displayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey)
            updateActivityDemand()
        }
    }
    @Published var inputRate: Double { didSet { persistRates() } }
    @Published var cachedInputRate: Double { didSet { persistRates() } }
    @Published var outputRate: Double { didSet { persistRates() } }
    @Published var currency: DisplayCurrency {
        didSet { UserDefaults.standard.set(currency.rawValue, forKey: Self.currencyKey) }
    }
    @Published private(set) var accounts: [AccountProfile]
    @Published var activeAccountID: UUID {
        didSet { UserDefaults.standard.set(activeAccountID.uuidString, forKey: Self.activeAccountKey) }
    }
    @Published private(set) var celebration: Celebration?
    private var client: CodexAppServerClient
    private let activityScanner = LocalActivityScanner()
    private let previewMode: Bool
    private var pollingTask: Task<Void, Never>?
    private var activityPollingTask: Task<Void, Never>?
    private var popoverVisible = false
    private var localActivityExpanded = true
    private var currentActivityDemand = ActivityRefreshDemand(
        popoverVisible: false,
        sectionExpanded: true,
        activityDisplaySelected: false
    )
    private var loginTasks: [UUID: Task<Void, Never>] = [:]
    private var celebrationDismissTask: Task<Void, Never>?
    private var lowUsageAlertState = LowUsageAlertState()
    private var lastUsageDiagnostics: String?
    private static let thresholdKey = "alertThreshold"
    private static let lowUsageAlertStateKey = "lowUsageAlertState"
    private static let displayModeKey = "menuBarDisplayMode"
    private static let inputRateKey = "costInputRate"
    private static let cachedInputRateKey = "costCachedInputRate"
    private static let outputRateKey = "costOutputRate"
    private static let currencyKey = "displayCurrency"
    private static let accountsKey = "accountProfiles"
    private static let activeAccountKey = "activeAccountID"
    private static let tokenMilestoneKey = "lastTokenMilestone"
    private static let resetMilestoneKey = "lastBankedReset"

    init(previewMode: Bool = false) {
        let defaultAccount = AccountProfile(id: Self.defaultAccountID, name: "Default", homePath: nil, email: nil)
        let loadedAccounts: [AccountProfile]
        if let data = UserDefaults.standard.data(forKey: Self.accountsKey),
           let decoded = try? JSONDecoder().decode([AccountProfile].self, from: data), !decoded.isEmpty {
            let separateAccounts = decoded.filter { $0.homePath != nil }
            loadedAccounts = [defaultAccount] + separateAccounts
        } else {
            loadedAccounts = [defaultAccount]
        }
        let savedAccount = UserDefaults.standard.string(forKey: Self.activeAccountKey).flatMap(UUID.init(uuidString:))
        let migratedSavedAccount = savedAccount.flatMap { candidate in
            decodedDefaultID(from: UserDefaults.standard.data(forKey: Self.accountsKey)) == candidate
                ? Self.defaultAccountID
                : candidate
        }
        let chosenAccountID = migratedSavedAccount.flatMap { candidate in
            loadedAccounts.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? Self.defaultAccountID
        self.previewMode = previewMode
        self.accounts = loadedAccounts
        self.activeAccountID = chosenAccountID
        self.client = CodexAppServerClient(codexHome: loadedAccounts.first(where: { $0.id == chosenAccountID })?.homeURL)
        UserDefaults.standard.set(try? JSONEncoder().encode(loadedAccounts), forKey: Self.accountsKey)
        UserDefaults.standard.set(chosenAccountID.uuidString, forKey: Self.activeAccountKey)
        let saved = UserDefaults.standard.integer(forKey: Self.thresholdKey)
        alertThreshold = saved == 0 ? 20 : saved
        displayMode = MenuBarDisplayMode(rawValue: UserDefaults.standard.string(forKey: Self.displayModeKey) ?? "") ?? .resetPercentageAndPace
        inputRate = UserDefaults.standard.double(forKey: Self.inputRateKey)
        cachedInputRate = UserDefaults.standard.double(forKey: Self.cachedInputRateKey)
        outputRate = UserDefaults.standard.double(forKey: Self.outputRateKey)
        currency = DisplayCurrency(rawValue: UserDefaults.standard.string(forKey: Self.currencyKey) ?? "") ?? .usd
        if let data = UserDefaults.standard.data(forKey: Self.lowUsageAlertStateKey),
           let decoded = try? JSONDecoder().decode(LowUsageAlertState.self, from: data) {
            lowUsageAlertState = decoded
        }
        if previewMode {
            let now = Date()
            payload = RateLimitPayload(
                snapshot: RateLimitSnapshot(
                    limitID: "codex",
                    limitName: "Codex",
                    planType: "plus",
                    primary: RateLimitWindow(usedPercent: 58, resetsAt: now.addingTimeInterval(8_040), durationMinutes: 300),
                    secondary: RateLimitWindow(usedPercent: 32, resetsAt: now.addingTimeInterval(403_200), durationMinutes: 10_080)
                ),
                fetchedAt: now,
                availableResetCredits: 3
            )
            let previewTokens: [Int64] = [8_000_000, 0, 5_000, 3_000_000, 0, 0, 9_000_000]
            activity = LocalActivitySnapshot(
                days: previewTokens.enumerated().map { offset, tokens in
                    DailyTokenUsage(
                        date: Calendar.current.date(byAdding: .day, value: offset - 6, to: Calendar.current.startOfDay(for: now)) ?? now,
                        usage: TokenUsage(inputTokens: tokens, cachedInputTokens: tokens / 2, outputTokens: tokens / 10, totalTokens: tokens)
                    )
                },
                models: [
                    ModelTokenUsage(model: "gpt-5.6-sol", usage: TokenUsage(inputTokens: 11_000_000, cachedInputTokens: 7_000_000, outputTokens: 1_000_000, totalTokens: 12_000_000)),
                    ModelTokenUsage(model: "gpt-5.6-terra", usage: TokenUsage(inputTokens: 7_000_000, cachedInputTokens: 4_000_000, outputTokens: 1_000_000, totalTokens: 8_000_000))
                ],
                sampledAt: now,
                filesRead: 12
            )
            if ProcessInfo.processInfo.arguments.contains("--preview-alert") {
                celebration = Celebration(title: "Usage running low", subtitle: "16% remains in weekly limit", symbol: "exclamationmark.triangle.fill")
            }
        }
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    var windows: [RateLimitWindow] { payload?.snapshot.windows ?? [] }
    var activeAccountName: String { accounts.first(where: { $0.id == activeAccountID })?.name ?? "Default" }
    var activeAccountDisplayName: String { accounts.first(where: { $0.id == activeAccountID })?.displayName ?? "Default" }
    var canDeleteActiveAccount: Bool { accounts.first(where: { $0.id == activeAccountID })?.homePath != nil }
    var bankedResetCount: Int? { payload?.availableResetCredits }
    var totalSavingsUSD: Double {
        guard let activity else { return 0 }
        guard let baseline = OpenAIPriceCatalog.price(for: "gpt-5.6-sol") else { return 0 }
        return activity.models.reduce(0) { total, item in
            guard let actual = OpenAIPriceCatalog.price(for: item.model) else { return total }
            return total + max(0, baseline.estimate(item.usage) - actual.estimate(item.usage))
        }
    }
    var totalSavings: Double { currency.convertFromUSD(totalSavingsUSD) }
    var menuBarRemaining: Int? {
        menuBarWindow?.remainingPercent
    }
    var menuBarWindow: RateLimitWindow? {
        guard errorMessage == nil, !isStale else { return nil }
        return payload?.snapshot.mostConstrainedWindow
    }
    var planLabel: String? {
        payload?.snapshot.planType?.replacingOccurrences(of: "_", with: " ").capitalized
    }
    var costRates: LocalCostRates {
        LocalCostRates(inputPerMillion: inputRate, cachedInputPerMillion: cachedInputRate, outputPerMillion: outputRate)
    }
    var isStale: Bool {
        guard let fetchedAt = payload?.fetchedAt else { return false }
        return Date().timeIntervalSince(fetchedAt) > 180
    }

    func start() {
        guard !previewMode else { return }
        pollingTask?.cancel()
        pollingTask = Task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
        updateActivityDemand()
    }

    func refreshActivity(force: Bool = false) async {
        guard !isActivityRefreshing else { return }
        if !force, let sampledAt = activity?.sampledAt,
           Date().timeIntervalSince(sampledAt) < 600 { return }
        isActivityRefreshing = true
        defer { isActivityRefreshing = false }
        do {
            activity = try await scanActivityWithTimeout()
            activityError = nil
            detectTokenMilestone(current: activity)
        } catch is CancellationError {
            return
        } catch {
            activityError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func scanActivityWithTimeout() async throws -> LocalActivitySnapshot {
        let scanner = activityScanner
        return try await withThrowingTaskGroup(of: LocalActivitySnapshot.self) { group in
            group.addTask { try await scanner.scan(days: 7) }
            group.addTask {
                try await Task.sleep(for: .seconds(45))
                throw LocalActivityError.timedOut
            }
            guard let result = try await group.next() else { throw LocalActivityError.timedOut }
            group.cancelAll()
            return result
        }
    }

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        updateActivityDemand()
    }

    func setLocalActivityExpanded(_ expanded: Bool) {
        localActivityExpanded = expanded
        updateActivityDemand()
    }

    private func updateActivityDemand() {
        guard !previewMode else { return }
        let demand = ActivityRefreshDemand(
            popoverVisible: popoverVisible,
            sectionExpanded: localActivityExpanded,
            activityDisplaySelected: displayMode == .activity
        )
        guard demand != currentActivityDemand else { return }
        currentActivityDemand = demand
        activityPollingTask?.cancel()
        activityPollingTask = nil
        if demand.requiresPolling {
            activityPollingTask = Task {
                await refreshActivity()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(600))
                    guard !Task.isCancelled else { break }
                    await refreshActivity()
                }
            }
        } else if demand.requiresRefresh {
            activityPollingTask = Task { await refreshActivity() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let newPayload = try await client.readRateLimits()
            let previous = payload
            payload = newPayload
            errorMessage = newPayload.snapshot.windows.isEmpty ? "No Codex rate-limit windows were returned for this account." : nil
            if errorMessage == nil {
                lastUsageDiagnostics = nil
                accountErrorMessage = nil
            }
            await notifyIfNeeded(newPayload)
            detectBankedResetMilestone(previous: previous, current: newPayload)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastUsageDiagnostics = await client.diagnosticSummary()
            await client.stop()
        }
    }

    func copyUsageDiagnostics() {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let text = [
            "Codex Meter diagnostics",
            "Version: \(appVersion)",
            "Time: \(Date().formatted(date: .numeric, time: .standard))",
            "Active profile: \(activeAccountName) (\(activeAccountID == Self.defaultAccountID ? "default CODEX_HOME" : "isolated CODEX_HOME"))",
            "Last successful refresh: \(payload?.fetchedAt.formatted(date: .numeric, time: .standard) ?? "none")",
            "Usage error: \(errorMessage ?? "none")",
            lastUsageDiagnostics ?? "Protocol diagnostics: unavailable"
        ].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            accountErrorMessage = "Launch at login could not be changed: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openCodex() {
        let settingsURL = URL(string: "codex://settings")
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first {
            running.activate(options: [.activateAllWindows])
            if let settingsURL { _ = NSWorkspace.shared.open(settingsURL) }
            return
        }
        let discoveredURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        let fallbackURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        guard let appURL = discoveredURL ?? (FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil) else {
            accountErrorMessage = "Codex is not installed in /Applications."
            return
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.accountErrorMessage = "Codex could not be opened: \(error.localizedDescription)"
                } else if let settingsURL {
                    _ = NSWorkspace.shared.open(settingsURL)
                }
            }
        }
    }

    func requestAccountSwitch(to id: UUID) {
        guard accounts.contains(where: { $0.id == id }), id != activeAccountID else { return }
        switchMeterAccount(to: id)
    }

    private func switchMeterAccount(to id: UUID) {
        guard accounts.contains(where: { $0.id == id }), id != activeAccountID else { return }
        pollingTask?.cancel()
        activityPollingTask?.cancel()
        Task {
            await client.stop()
            let profile = accounts.first(where: { $0.id == id })
            activeAccountID = id
            client = CodexAppServerClient(codexHome: profile?.homeURL)
            payload = nil
            activity = nil
            start()
        }
    }

    func addAccount() {
        let alert = NSAlert()
        alert.messageText = "Add Codex account"
        alert.informativeText = "Choose a label. Codex Meter will open OpenAI's secure browser sign-in for a private profile on this Mac. Passwords and verification codes stay on OpenAI's page."
        let field = NSTextField(string: "Work")
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let id = UUID()
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-meter", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let config = home.appendingPathComponent("config.toml")
            if !FileManager.default.fileExists(atPath: config.path) {
                try Data("cli_auth_credentials_store = \"file\"\n".utf8).write(to: config, options: .atomic)
            }
            let profile = AccountProfile(id: id, name: name, homePath: home.path, email: nil)
            accounts.append(profile)
            persistAccounts()
            startLogin(for: profile)
        } catch {
            accountErrorMessage = "The account profile could not be created: \(error.localizedDescription)"
        }
    }

    func deleteActiveAccount() {
        deleteAccount(id: activeAccountID)
    }

    func deleteAccount(id: UUID) {
        guard let profile = accounts.first(where: { $0.id == id }), let home = profile.homeURL else { return }
        let wasActive = profile.id == activeAccountID
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \(profile.name)?"
        alert.informativeText = "This removes the locally saved Codex credentials and usage profile from this Mac. It does not delete the OpenAI account."
        alert.addButton(withTitle: "Delete Account")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if wasActive {
            pollingTask?.cancel()
            activityPollingTask?.cancel()
        }
        Task {
            if wasActive { await client.stop() }
            do {
                loginTasks.removeValue(forKey: profile.id)?.cancel()
                try AccountProfileStorage.removeLocalProfile(at: home)
                accounts.removeAll { $0.id == profile.id }
                persistAccounts()
                if wasActive, let fallback = accounts.first {
                    activeAccountID = fallback.id
                    client = CodexAppServerClient(codexHome: fallback.homeURL)
                    payload = nil
                    activity = nil
                    start()
                }
                showCelebration(Celebration(title: "Account removed", subtitle: "Local credentials were deleted", symbol: "trash"))
            } catch {
                if wasActive {
                    client = CodexAppServerClient(codexHome: profile.homeURL)
                    start()
                }
                accountErrorMessage = "The local account could not be deleted: \(error.localizedDescription)"
            }
        }
    }

    private func startLogin(for profile: AccountProfile) {
        guard let home = profile.homeURL else { return }
        accountErrorMessage = nil
        loginTasks[profile.id]?.cancel()
        loginTasks[profile.id] = Task { [weak self] in
            guard let self else { return }
            let loginClient = CodexAppServerClient(codexHome: home)
            do {
                let login = try await loginClient.startChatGPTLogin()
                guard NSWorkspace.shared.open(login.authorizationURL) else {
                    throw CodexClientError.server("The OpenAI sign-in page could not be opened in your browser.")
                }
                try await loginClient.waitForLogin(id: login.id)
                guard let account = try await loginClient.readAccount(refreshToken: true) else {
                    throw CodexClientError.server("Codex did not report a signed-in account after login.")
                }
                await loginClient.stop()
                self.loginTasks.removeValue(forKey: profile.id)
                if let index = self.accounts.firstIndex(where: { $0.id == profile.id }) {
                    self.accounts[index].email = account.email
                    self.persistAccounts()
                }
                self.switchMeterAccount(to: profile.id)
                self.showCelebration(Celebration(title: "Account ready", subtitle: "Secure sign-in completed", symbol: "person.crop.circle.badge.checkmark"))
            } catch is CancellationError {
                await loginClient.stop()
            } catch {
                await loginClient.stop()
                self.loginTasks.removeValue(forKey: profile.id)
                self.accounts.removeAll { $0.id == profile.id }
                self.persistAccounts()
                try? AccountProfileStorage.removeLocalProfile(at: home)
                self.accountErrorMessage = "OpenAI sign-in failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
        }
    }

    private func persistAccounts() {
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: Self.accountsKey)
    }

    private func detectTokenMilestone(current: LocalActivitySnapshot?) {
        guard !previewMode, let current else { return }
        let newTokens = current.total.totalTokens
        let tokenStep = max(0, Int(newTokens / 1_000_000))
        let oldTokenStep = UserDefaults.standard.integer(forKey: Self.tokenMilestoneKey)
        if tokenStep >= 1, tokenStep > oldTokenStep, (tokenStep % 10 == 0 || oldTokenStep == 0) {
            UserDefaults.standard.set(tokenStep, forKey: Self.tokenMilestoneKey)
            showCelebration(Celebration(title: "Token milestone", subtitle: "This Mac recorded \(tokenStep)M tokens", symbol: "bolt.fill"))
        }
    }

    private func detectBankedResetMilestone(previous: RateLimitPayload?, current: RateLimitPayload) {
        guard !previewMode,
              let previousCount = previous?.availableResetCredits,
              let currentCount = current.availableResetCredits,
              currentCount > previousCount else { return }
        let key = "\(activeAccountID.uuidString)-\(currentCount)"
        guard UserDefaults.standard.string(forKey: Self.resetMilestoneKey) != key else { return }
        UserDefaults.standard.set(key, forKey: Self.resetMilestoneKey)
        showCelebration(Celebration(title: "Reset banked", subtitle: "\(currentCount) available for this account", symbol: "arrow.counterclockwise.circle.fill"))
    }

    func dismissCelebration() {
        celebrationDismissTask?.cancel()
        celebrationDismissTask = nil
        celebration = nil
    }

    private func showCelebration(_ newCelebration: Celebration) {
        celebrationDismissTask?.cancel()
        celebration = newCelebration
        celebrationDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.celebration = nil
        }
    }

    private func notifyIfNeeded(_ payload: RateLimitPayload) async {
        guard let constrained = payload.snapshot.mostConstrainedWindow else { return }

        let fallbackBucket = Int(Date().timeIntervalSince1970 / 86_400)
        let resetComponent = constrained.resetsAt.map { Int($0.timeIntervalSince1970) } ?? fallbackBucket
        let resetID = "\(activeAccountID.uuidString)-\(constrained.durationMinutes ?? 0)-\(resetComponent)"
        let shouldAlert = lowUsageAlertState.observe(
            windowID: resetID,
            remainingPercent: constrained.remainingPercent,
            threshold: alertThreshold
        )
        if let encoded = try? JSONEncoder().encode(lowUsageAlertState) {
            UserDefaults.standard.set(encoded, forKey: Self.lowUsageAlertStateKey)
        }
        guard shouldAlert else { return }

        if !previewMode {
            showCelebration(Celebration(
                title: "Usage running low",
                subtitle: "\(constrained.remainingPercent)% remains in \(constrained.displayName.lowercased())",
                symbol: "exclamationmark.triangle.fill"
            ))
        }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Codex usage is running low"
        content.body = "\(constrained.remainingPercent)% remains. \(ResetTimeFormatter.notificationText(for: constrained.resetsAt))"
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "codex-meter-low-\(resetID)", content: content, trigger: nil))
    }

    private func persistRates() {
        UserDefaults.standard.set(max(0, inputRate), forKey: Self.inputRateKey)
        UserDefaults.standard.set(max(0, cachedInputRate), forKey: Self.cachedInputRateKey)
        UserDefaults.standard.set(max(0, outputRate), forKey: Self.outputRateKey)
    }
}

private func decodedDefaultID(from data: Data?) -> UUID? {
    guard let data,
          let decoded = try? JSONDecoder().decode([AccountProfile].self, from: data) else { return nil }
    return decoded.first(where: { $0.homePath == nil })?.id
}

enum ResetTimeFormatter {
    static func relativeText(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset time unavailable" }
        if date <= now { return "Resetting now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Resets \(formatter.localizedString(for: date, relativeTo: now))"
    }

    static func absoluteText(for date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func notificationText(for date: Date?) -> String {
        guard let date else { return "The reset time is unavailable." }
        return "It resets \(date.formatted(date: .omitted, time: .shortened))."
    }
}
