import Charts
import CodexMeterCore
import SwiftUI

struct MeterView: View {
    @ObservedObject var store: UsageStore
    let onPreferredSizeChange: (NSSize) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("localActivityExpanded") private var localActivityExpanded = true
    @AppStorage("settingsExpanded") private var settingsExpanded = false
    @State private var panelContentHeight: CGFloat = 1

    init(store: UsageStore, onPreferredSizeChange: @escaping (NSSize) -> Void = { _ in }) {
        self.store = store
        self.onPreferredSizeChange = onPreferredSizeChange
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    panelSections
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: PanelHeightKey.self, value: geometry.size.height)
                            }
                        }
                }
                .scrollDisabled(panelContentHeight <= maximumPanelHeight)
                .frame(height: min(panelContentHeight, maximumPanelHeight), alignment: .top)
            }
            .allowsHitTesting(store.celebration == nil)
            if let celebration = store.celebration {
                CelebrationBanner(celebration: celebration, dismiss: store.dismissCelebration)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.celebration)
        .frame(width: 348)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.42), lineWidth: 0.75)
        }
        .onAppear { store.setLocalActivityExpanded(localActivityExpanded) }
        .onPreferenceChange(PanelHeightKey.self) { height in
            panelContentHeight = max(1, height)
            onPreferredSizeChange(NSSize(width: 348, height: min(max(1, height), maximumPanelHeight) + 82))
        }
        .onChange(of: localActivityExpanded) { expanded in
            store.setLocalActivityExpanded(expanded)
        }
    }

    private var maximumPanelHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return min(700, max(260, screenHeight * 0.82 - 82))
    }

    private var panelSections: some View {
        VStack(spacing: 0) {
            content
            Divider()
            settings
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Meter")
                    .font(.system(size: 15, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            accountMenu
            VStack(spacing: 1) {
                Button {
                    Task {
                        await store.refresh()
                        await store.refreshActivity()
                    }
                } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .help("Refresh usage")
                .disabled(store.isRefreshing)
                .accessibilityLabel("Refresh Codex usage")
                Text(refreshCaption)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(store.isStale ? Color.orange : Color.secondary)
            }
            .frame(width: 38)
        }
        .padding(16)
    }

    private var accountMenu: some View {
        Menu {
            Section("Use account") {
                ForEach(store.accounts) { account in
                    Button {
                        store.requestAccountSwitch(to: account.id)
                    } label: {
                        if account.id == store.activeAccountID {
                            Label(account.displayName, systemImage: "checkmark")
                        } else {
                            Text(account.displayName)
                        }
                    }
                    .disabled(account.id == store.activeAccountID)
                }
            }
            Divider()
            Button("Add account…", systemImage: "person.badge.plus") {
                store.addAccount()
            }
            let removableAccounts = store.accounts.filter { $0.homePath != nil }
            if !removableAccounts.isEmpty {
                Menu("Delete account", systemImage: "trash") {
                    ForEach(removableAccounts) { account in
                        Button(account.displayName, role: .destructive) {
                            store.deleteAccount(id: account.id)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                Text(store.activeAccountDisplayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .frame(maxWidth: 92)
        }
        .menuStyle(.borderlessButton)
        .focusable(false)
        .fixedSize()
        .help("Switch Codex Meter usage account")
        .accessibilityLabel("Current account: \(store.activeAccountDisplayName). Open account switcher")
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            quotaContent
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 0.6)
            }
            if let activity = store.activity {
                Divider()
                DisclosureGroup(isExpanded: $localActivityExpanded) {
                    ThisMacActivityView(activity: activity, weeklyResetDates: store.weeklyResetDates)
                } label: {
                    SectionLabel(title: "This Mac activity", detail: "\(compactTokens(activity.total.totalTokens)) tokens")
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 0.6)
                }
            } else if store.isActivityRefreshing {
                Divider()
                DisclosureGroup(isExpanded: $localActivityExpanded) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scanning recent logs on this Mac…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.top, 10)
                } label: {
                    SectionLabel(title: "This Mac activity", detail: "Updating")
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 0.6)
                }
            } else if let activityError = store.activityError {
                Divider()
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This Mac activity unavailable")
                            .font(.system(size: 11, weight: .medium))
                        Text(activityError)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
            } else {
                Divider()
                DisclosureGroup(isExpanded: $localActivityExpanded) {
                    Text("Open this section to scan recent Codex session logs on this Mac.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                } label: {
                    SectionLabel(title: "This Mac activity", detail: "Open to scan")
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 0.6)
                }
            }
        }
    }

    @ViewBuilder
    private var quotaContent: some View {
        if store.payload == nil && store.isRefreshing {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking Codex usage…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 148)
        } else if store.windows.isEmpty {
            VStack(spacing: 0) {
                if store.bankedResetCount != nil {
                    bankedResetsRow
                    Divider().padding(.leading, 16)
                }
                EmptyState(message: store.errorMessage ?? "Usage data is unavailable.", retry: {
                    Task { await store.refresh() }
                }, copyDiagnostics: store.copyUsageDiagnostics)
            }
        } else {
            VStack(spacing: 0) {
                bankedResetsRow
                Divider().padding(.leading, 16)
                ForEach(Array(store.windows.enumerated()), id: \.offset) { index, window in
                    UsageRow(window: window, now: store.payload?.fetchedAt ?? Date())
                    if index < store.windows.count - 1 { Divider().padding(.leading, 16) }
                }
                if let error = store.errorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Copy Diagnostics", action: store.copyUsageDiagnostics)
                            .font(.system(size: 9, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var bankedResetsRow: some View {
        let count = store.bankedResetCount
        return HStack(spacing: 8) {
            Image(systemName: "arrow.counterclockwise.circle")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Banked resets")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            if let count {
                Text("\(count) available")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("Unavailable")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .help(count == nil
            ? "OpenAI did not return a banked reset count for this account"
            : "Manual reset credits for this account")
    }

    private var settings: some View {
        DisclosureGroup(isExpanded: $settingsExpanded) {
            footer
        } label: {
            HStack {
                Text("Settings").font(.system(size: 12, weight: .medium))
                Spacer()
                if store.accountErrorMessage != nil {
                    Text("Account needs attention")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 0.6)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let accountError = store.accountErrorMessage {
                Text(accountError)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Menu bar")
                    .font(.system(size: 12))
                Spacer()
                Picker("Menu bar display", selection: $store.displayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .font(.system(size: 10))
                .frame(width: 210)
            }
            HStack {
                Text("Low-usage alert")
                    .font(.system(size: 12))
                Spacer()
                Picker("Low-usage alert", selection: $store.alertThreshold) {
                    Text("10%").tag(10)
                    Text("20%").tag(20)
                    Text("30%").tag(30)
                }
                .labelsHidden()
                .frame(width: 72)
            }
            Toggle("Launch at login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            .font(.system(size: 12))
            Divider()
            updates
            Divider()
            HStack {
                Button("Open Codex") { store.openCodex() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            Divider()
            credits
        }
        .padding(.top, 10)
    }

    private var updates: some View {
        let channel = store.selectedUpdateChannel
        let result = store.updateResult(for: channel)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Updates")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("Installed \(store.currentAppVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            HStack {
                if store.isCheckingForUpdates {
                    Text("Checking…").foregroundStyle(.secondary)
                } else if let release = result?.release, release.isNewer(than: store.currentAppVersion) {
                    Button("View \(release.version) release") { store.openRelease(for: channel) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                } else if let error = result?.errorMessage {
                    Text("Update check failed")
                        .foregroundStyle(.orange)
                        .help(error)
                } else {
                    Text(result == nil ? "Not checked" : "Up to date")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check for Updates") { Task { await store.checkForUpdates() } }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(store.isCheckingForUpdates)
            }
            .font(.system(size: 11))

            Toggle("Check for updates automatically", isOn: $store.automaticallyChecksForUpdates)
                .font(.system(size: 12))

            DisclosureGroup("Advanced") {
                Picker("Update source", selection: $store.selectedUpdateChannel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11))
        }
    }

    private var credits: some View {
        HStack(alignment: .center, spacing: 11) {
            if let signature = Self.creatorSignature {
                Link(destination: URL(string: "https://matthewvroom.com/")!) {
                    Image(nsImage: signature)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.primary)
                        .frame(width: 56, height: 80)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Visit Matthew Vroom’s portfolio")
                .help("Visit Matthew Vroom’s portfolio")
            }

            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reimagined by")
                        .foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            creatorName
                            Spacer(minLength: 0)
                            creatorLinks
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            creatorName
                            HStack {
                                Spacer(minLength: 0)
                                creatorLinks
                            }
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Originally created by")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        Spacer(minLength: 0)
                        originalCreatorLink
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Originally created by")
                            .foregroundStyle(.secondary)
                        HStack {
                            Spacer(minLength: 0)
                            originalCreatorLink
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var creatorName: some View {
        Text("Matthew Vroom")
            .font(.system(size: 13, weight: .semibold))
            .fixedSize()
    }

    private var creatorLinks: some View {
        HStack(spacing: 10) {
            Link("GitHub", destination: URL(string: "https://github.com/matthewvroom")!)
            Link("Portfolio", destination: URL(string: "https://matthewvroom.com/")!)
        }
        .fixedSize()
    }

    private var originalCreatorLink: some View {
        Link("Jhye / The Jhye Factor", destination: URL(string: "https://github.com/TheJhyeFactor")!)
            .fixedSize()
    }

    private static let creatorSignature: NSImage? = {
        guard let url = Bundle.main.url(forResource: "CreatorSignature", withExtension: "svg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    private var headerSubtitle: String {
        if store.isStale { return "Usage data is stale" }
        if let plan = store.planLabel { return "\(plan) plan" }
        return "Signed in through the Codex app"
    }

    private var refreshCaption: String {
        if store.isRefreshing { return "Now" }
        guard let date = store.payload?.fetchedAt else { return "--" }
        let localized = date.formatted(date: .omitted, time: .shortened)
        return String(localized.prefix(while: { !$0.isWhitespace }))
    }

}

private func compactTokens(_ value: Int64) -> String {
    if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
    return "\(value)"
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SectionLabel: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

private struct CelebrationBanner: View {
    let celebration: Celebration
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: celebration.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(celebration.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(celebration.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.accentColor.opacity(0.55), lineWidth: 1))
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}

private struct ThisMacActivityView: View {
    let activity: LocalActivitySnapshot
    let weeklyResetDates: [Date]
    @AppStorage("localActivityDetailsExpanded") private var detailsExpanded = false
    @State private var showsAllModels = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last seven days")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let firstDay = activity.days.first?.date,
               let lastDay = activity.days.last?.date,
               let dayAfterLast = Calendar.current.date(byAdding: .day, value: 1, to: lastDay) {
                activityChart(from: firstDay, through: dayAfterLast)
            }

            if !resetDays.isEmpty {
                HStack(spacing: 6) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 1))
                        path.addLine(to: CGPoint(x: 14, y: 1))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 14, height: 2)
                    .accessibilityHidden(true)
                    Text("Weekly quota reset")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            if activity.summarizedLargeFiles > 0 {
                Text("Includes partial logs")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Details", isExpanded: $detailsExpanded) {
                activityDetails
                    .padding(.top, 8)
            }
            .font(.system(size: 11))
        }
        .padding(.top, 8)
    }

    private func activityChart(from firstDay: Date, through dayAfterLast: Date) -> some View {
        Chart {
            ForEach(activity.days) { day in
                if day.usage.totalTokens == 0 {
                    PointMark(x: .value("Day", day.date, unit: .day), y: .value("Tokens", 0))
                        .symbolSize(9)
                        .foregroundStyle(Color.secondary.opacity(0.55))
                        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                        .accessibilityValue("0 tokens")
                } else {
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Tokens", visibleTokenValue(day.usage.totalTokens))
                    )
                    .foregroundStyle(day.id == activity.days.last?.id ? Color.accentColor : Color.accentColor.opacity(0.62))
                    .cornerRadius(2)
                    .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue("\(day.usage.totalTokens) tokens")
                }
            }
            ForEach(resetDays, id: \.self) { day in
                if let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) {
                    RuleMark(x: .value("Day after reset", nextDay))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .foregroundStyle(Color.secondary)
                        .accessibilityLabel("Weekly quota reset")
                        .accessibilityValue(day.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .chartXScale(domain: firstDay...dayAfterLast, range: .plotDimension(padding: 4))
        .chartXAxis {
            AxisMarks(values: activity.days.map(\.date)) {
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 76)
        .accessibilityLabel("Seven-day token activity recorded on this Mac")
        .accessibilityValue(accessibilitySummary)
    }

    private var activityDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today \(compactTokens(activity.today.totalTokens))")
                Spacer()
                Text("Updated \(activity.sampledAt.formatted(date: .omitted, time: .shortened))")
            }
            .foregroundStyle(.secondary)

            if activity.summarizedLargeFiles > 0 {
                Text("Only recent entries were read from \(activity.summarizedLargeFiles) large logs. Totals may be incomplete.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(activity.models.prefix(showsAllModels ? activity.models.count : 4)) { item in
                LabeledContent {
                    Text(modelShare(item))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } label: {
                    Text(item.model)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
            }
            if activity.models.count > 4 {
                Button(showsAllModels ? "Show top models" : "Show all \(activity.models.count) models") {
                    showsAllModels.toggle()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            ForEach(resetDays, id: \.self) { day in
                LabeledContent("Weekly quota reset", value: day.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    private var resetDays: [Date] {
        let days = Set(activity.days.map(\.date))
        return Set(weeklyResetDates.map { Calendar.current.startOfDay(for: $0) }).intersection(days).sorted()
    }

    private func modelShare(_ item: ModelTokenUsage) -> String {
        guard activity.total.totalTokens > 0 else { return "0%" }
        return "\(Int((Double(item.usage.totalTokens) / Double(activity.total.totalTokens) * 100).rounded()))% · \(compactTokens(item.usage.totalTokens))"
    }

    private var accessibilitySummary: String {
        let dailyTotals = activity.days.map { day in
            "\(day.date.formatted(.dateTime.weekday(.wide))): \(day.usage.totalTokens) tokens"
        }
        let resets = resetDays.map { day in
            "Weekly quota reset on \(day.formatted(date: .abbreviated, time: .omitted))"
        }
        return (dailyTotals + resets).joined(separator: ", ")
    }

    private func visibleTokenValue(_ tokens: Int64) -> Double {
        let maximum = Double(activity.days.map(\.usage.totalTokens).max() ?? 1)
        return max(Double(tokens), maximum * 0.035)
    }
}

private struct UsageRow: View {
    let window: RateLimitWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(window.displayName)
                            .font(.system(size: 12, weight: .medium))
                        if let warningText {
                            Text(warningText)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(meterColor)
                        }
                    }
                    Text(ResetTimeFormatter.relativeText(for: window.resetsAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(window.remainingPercent)%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("remaining")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let absoluteReset = ResetTimeFormatter.absoluteText(for: window.resetsAt) {
                        Text(absoluteReset)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(window.remainingPercent) percent remaining")
            }

            UsageProgressBar(remainingPercent: window.remainingPercent, color: meterColor)
                .animation(.easeInOut(duration: 0.45), value: window.remainingPercent)
                .accessibilityLabel(window.displayName)
                .accessibilityValue([
                    "\(window.remainingPercent) percent remaining.",
                    ResetTimeFormatter.relativeText(for: window.resetsAt),
                    ResetTimeFormatter.absoluteText(for: window.resetsAt)
                ].compactMap { $0 }.joined(separator: " "))

            if let pace = WeeklyPace(window: window, now: now) {
                Divider()
                WeeklyPaceView(pace: pace)
            }
        }
        .padding(16)
    }

    private var meterColor: Color {
        if window.remainingPercent <= 10 { return .red }
        if window.remainingPercent <= 25 { return .orange }
        return .accentColor
    }

    private var warningText: String? {
        if window.remainingPercent <= 10 { return "Nearly exhausted" }
        if window.remainingPercent <= 25 { return "Running low" }
        return nil
    }
}

private struct UsageProgressBar: View {
    let remainingPercent: Int
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(height: 8)
                Capsule()
                    .fill(color)
                    .frame(width: width * CGFloat(remainingPercent) / 100, height: 8)
                ForEach(0...8, id: \.self) { index in
                    Rectangle()
                        .fill(Color.primary.opacity(index.isMultiple(of: 2) ? 0.24 : 0.12))
                        .frame(width: 1, height: index.isMultiple(of: 2) ? 14 : 10)
                        .position(x: min(max(width * CGFloat(index) / 8, 0.5), width - 0.5), y: 7)
                }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
    }
}

private struct WeeklyPaceView: View {
    let pace: WeeklyPace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly pace")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(pace.summaryText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PacePalette.color(for: pace.deltaPoints))
            }
            Text("\(rounded(pace.actualUsedPercent))% used · \(rounded(pace.expectedUsedPercent))% expected by now")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            PaceBar(pace: pace)
            HStack {
                Text("−50%")
                Spacer()
                Text("On pace")
                Spacer()
                Text("+50%")
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weekly pace")
        .accessibilityValue("\(pace.summaryText). \(rounded(pace.actualUsedPercent)) percent used; \(rounded(pace.expectedUsedPercent)) percent expected by now.")
    }

    private func rounded(_ value: Double) -> Int { Int(value.rounded()) }
}

private struct PaceBar: View {
    let pace: WeeklyPace

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let center = width / 2
            let marker = width * CGFloat((pace.markerPosition + 1) / 2)
            let color = PacePalette.color(for: pace.deltaPoints)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.22)).frame(height: 8)
                Capsule()
                    .fill(color)
                    .frame(width: abs(marker - center), height: 8)
                    .position(x: (marker + center) / 2, y: 9)
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 1, height: 13)
                    .position(x: center, y: 5.5)
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(Circle().stroke(color, lineWidth: 3))
                    .frame(width: 13, height: 13)
                    .position(x: marker, y: 9)
            }
            .frame(height: 18)
        }
        .frame(height: 18)
    }
}

private enum PacePalette {
    static func color(for delta: Double) -> Color {
        guard delta > 0 else { return Color(nsColor: .systemGreen) }
        let stops: [(Double, NSColor)] = [
            (0, .systemGreen),
            (12.5, .systemYellow),
            (25, .systemOrange),
            (37.5, .systemRed),
            (50, NSColor(calibratedRed: 0.55, green: 0.02, blue: 0.04, alpha: 1))
        ]
        let clamped = min(delta, 50)
        for index in 1..<stops.count where clamped <= stops[index].0 {
            let lower = stops[index - 1]
            let upper = stops[index]
            let fraction = (clamped - lower.0) / (upper.0 - lower.0)
            return Color(nsColor: lower.1.blended(withFraction: fraction, of: upper.1) ?? upper.1)
        }
        return Color(nsColor: stops.last!.1)
    }
}

private struct EmptyState: View {
    let message: String
    let retry: () -> Void
    let copyDiagnostics: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Usage unavailable")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            HStack(spacing: 10) {
                Button("Try again", action: retry)
                Button("Copy Diagnostics", action: copyDiagnostics)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 166)
        .padding(.horizontal, 20)
    }
}
