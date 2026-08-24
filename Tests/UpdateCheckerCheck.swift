import Foundation
#if canImport(CodexMeterCore)
import CodexMeterCore
#endif

@main
struct UpdateCheckerCheck {
    static func main() throws {
        precondition(SemanticVersion("v1.6.5") == SemanticVersion("1.6.5"))
        precondition(SemanticVersion("1.7")! > SemanticVersion("1.6.5")!)
        precondition(SemanticVersion("1.6.5")! > SemanticVersion("1.6.4")!)
        precondition(SemanticVersion("nonsense") == nil)
        precondition(UpdateChannel.matthewFork.owner == "matthewvroom")
        precondition(UpdateChannel.original.owner == "TheJhyeFactor")

        let payload = Data(#"{"tag_name":"v1.6.5","name":"Codex Meter 1.6.5","html_url":"https://github.com/matthewvroom/codex-meter/releases/tag/v1.6.5","draft":false,"prerelease":false,"published_at":"2026-08-24T20:00:00Z"}"#.utf8)
        let release = try GitHubReleaseParser.parse(data: payload, statusCode: 200)
        precondition(release.version == "1.6.5")
        precondition(release.isNewer(than: "1.6.4"))
        precondition(!release.isNewer(than: "1.6.5"))

        let selected = UpdateChannelResult(channel: .matthewFork, release: release, errorMessage: nil)
        let originalRelease = GitHubRelease(
            version: "1.5.0",
            tagName: "v1.5.0",
            name: "Codex Meter 1.5.0",
            releaseURL: UpdateChannel.original.repositoryURL,
            publishedAt: nil
        )
        let original = UpdateChannelResult(channel: .original, release: originalRelease, errorMessage: nil)
        precondition(UpdatePolicy.selectedRelease(in: [selected, original], selectedChannel: .matthewFork, currentVersion: "1.6.4") == release)
        precondition(UpdatePolicy.selectedRelease(in: [selected, original], selectedChannel: .original, currentVersion: "1.6.4") == nil)
        precondition(UpdatePolicy.hasNewerUnselectedRelease(in: [selected, original], selectedChannel: .original, currentVersion: "1.6.4"))

        let prerelease = Data(#"{"tag_name":"v1.7.0-beta","name":"Beta","html_url":"https://example.com","draft":false,"prerelease":true}"#.utf8)
        expect(.malformedResponse) { try GitHubReleaseParser.parse(data: prerelease, statusCode: 200) }
        expect(.malformedResponse) { try GitHubReleaseParser.parse(data: Data("{}".utf8), statusCode: 200) }
        expect(.unavailable(404)) { try GitHubReleaseParser.parse(data: payload, statusCode: 404) }
        expect(.unavailable(403)) { try GitHubReleaseParser.parse(data: payload, statusCode: 403) }
        let invalidVersion = Data(#"{"tag_name":"latest","name":"Latest","html_url":"https://example.com","draft":false,"prerelease":false}"#.utf8)
        expect(.invalidVersion) { try GitHubReleaseParser.parse(data: invalidVersion, statusCode: 200) }
        print("Update checker checks passed")
    }

    private static func expect(_ expected: UpdateCheckError, operation: () throws -> GitHubRelease) {
        do {
            _ = try operation()
            preconditionFailure("Expected \(expected)")
        } catch let error as UpdateCheckError {
            precondition(error == expected)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }
}
