import Foundation

public enum UpdateChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case matthewFork
    case original

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .matthewFork: return "Matthew's Fork"
        case .original: return "Original Project"
        }
    }

    public var owner: String {
        switch self {
        case .matthewFork: return "matthewvroom"
        case .original: return "TheJhyeFactor"
        }
    }

    public var repository: String { "codex-meter" }
    public var latestReleaseURL: URL { URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")! }
    public var repositoryURL: URL { URL(string: "https://github.com/\(owner)/\(repository)")! }
}

public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.first?.lowercased() == "v" ? String(trimmed.dropFirst()) : trimmed
        let stablePart = withoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? withoutPrefix
        let components = stablePart.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = components.count == 3 ? Int(components[2]) : 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct GitHubRelease: Equatable, Sendable {
    public let version: String
    public let tagName: String
    public let name: String
    public let releaseURL: URL
    public let publishedAt: Date?

    public init(version: String, tagName: String, name: String, releaseURL: URL, publishedAt: Date?) {
        self.version = version
        self.tagName = tagName
        self.name = name
        self.releaseURL = releaseURL
        self.publishedAt = publishedAt
    }

    public func isNewer(than currentVersion: String) -> Bool {
        guard let latest = SemanticVersion(version), let current = SemanticVersion(currentVersion) else { return false }
        return latest > current
    }
}

public struct UpdateChannelResult: Equatable, Identifiable, Sendable {
    public let channel: UpdateChannel
    public let release: GitHubRelease?
    public let errorMessage: String?
    public let checkedAt: Date
    public var id: UpdateChannel { channel }

    public init(channel: UpdateChannel, release: GitHubRelease?, errorMessage: String?, checkedAt: Date = Date()) {
        self.channel = channel
        self.release = release
        self.errorMessage = errorMessage
        self.checkedAt = checkedAt
    }
}

public enum UpdateCheckError: LocalizedError, Equatable {
    case unavailable(Int)
    case malformedResponse
    case invalidVersion

    public var errorDescription: String? {
        switch self {
        case .unavailable(let status): return "GitHub returned HTTP \(status)."
        case .malformedResponse: return "GitHub returned an unreadable release response."
        case .invalidVersion: return "The latest release has an invalid version number."
        }
    }
}

public enum GitHubReleaseParser {
    private struct ReleaseResponse: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let publishedAt: Date?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case draft
            case prerelease
            case publishedAt = "published_at"
        }
    }

    public static func parse(data: Data, statusCode: Int) throws -> GitHubRelease {
        guard statusCode == 200 else { throw UpdateCheckError.unavailable(statusCode) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(ReleaseResponse.self, from: data),
              !decoded.draft, !decoded.prerelease else { throw UpdateCheckError.malformedResponse }
        let version = decoded.tagName.first?.lowercased() == "v" ? String(decoded.tagName.dropFirst()) : decoded.tagName
        guard SemanticVersion(version) != nil else { throw UpdateCheckError.invalidVersion }
        return GitHubRelease(
            version: version,
            tagName: decoded.tagName,
            name: decoded.name ?? decoded.tagName,
            releaseURL: decoded.htmlURL,
            publishedAt: decoded.publishedAt
        )
    }
}

public enum UpdatePolicy {
    public static func selectedRelease(
        in results: [UpdateChannelResult],
        selectedChannel: UpdateChannel,
        currentVersion: String
    ) -> GitHubRelease? {
        results.first(where: { $0.channel == selectedChannel })?.release.flatMap {
            $0.isNewer(than: currentVersion) ? $0 : nil
        }
    }

    public static func hasNewerUnselectedRelease(
        in results: [UpdateChannelResult],
        selectedChannel: UpdateChannel,
        currentVersion: String
    ) -> Bool {
        results.contains {
            $0.channel != selectedChannel && $0.release?.isNewer(than: currentVersion) == true
        }
    }
}

public actor UpdateChecker {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func check(_ channel: UpdateChannel, now: Date = Date()) async -> UpdateChannelResult {
        var request = URLRequest(url: channel.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Codex-Meter", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.malformedResponse }
            guard http.statusCode == 200 else { throw UpdateCheckError.unavailable(http.statusCode) }
            let release = try GitHubReleaseParser.parse(data: data, statusCode: http.statusCode)
            return UpdateChannelResult(
                channel: channel,
                release: release,
                errorMessage: nil,
                checkedAt: now
            )
        } catch {
            return UpdateChannelResult(
                channel: channel,
                release: nil,
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                checkedAt: now
            )
        }
    }

    public func checkAll(now: Date = Date()) async -> [UpdateChannelResult] {
        await withTaskGroup(of: UpdateChannelResult.self) { group in
            for channel in UpdateChannel.allCases {
                group.addTask { await self.check(channel, now: now) }
            }
            var results: [UpdateChannelResult] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.channel.rawValue < $1.channel.rawValue }
        }
    }
}
