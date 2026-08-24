# Architecture

Codex Meter is a SwiftUI/AppKit status-bar application with six small layers:

1. `AppDelegate` owns `NSStatusItem` and `NSPopover` lifecycle.
2. `UsageStore` owns polling, preferences, login-item registration, and low-usage notifications.
3. `CodexAppServerClient` owns one local stdio JSONL session with `codex app-server`.
4. `RateLimitParser` converts versioned app-server payloads into stable UI models.
5. `LocalActivityScanner` filters aggregate-only token events from local rollout logs, deduplicates them and produces daily buckets.
6. `CodexMeterCLI` exposes stable status/history DTOs for local scripts without importing AppKit.

`UsageStore` can select an isolated account profile. Each profile is a Codex-owned `CODEX_HOME` directory with file-scoped credential storage, and the client starts `codex app-server` with that environment only. Adding a profile invokes Codex's supported browser login flow and activates the account only after login succeeds; Codex Meter never inspects the profile's credentials.

Account deletion removes the selected non-default profile only after a native confirmation. Missing profile folders are treated as an already-completed filesystem removal so stale account records can still be cleared.

The desktop Codex app uses the default Codex authentication profile. A confirmed **Meter + Codex** switch closes the desktop app, creates a default-home app-server connection, calls the documented `account/logout` method, starts `account/login/start` with ChatGPT browser authentication, waits for `account/login/completed`, verifies the result with `account/read`, and relaunches Codex. This is deliberately a fresh OAuth flow: Codex Meter does not copy tokens between profiles, collect passwords or MFA codes, call internal token-login modes, or request Accessibility control.

The client performs the required `initialize` handshake before calling `account/rateLimits/read`. It prefers the `codex` entry in the multi-bucket response and falls back to the backward-compatible single-bucket response. Percentages are clamped to 0–100, and the menu bar displays the lowest remaining percentage across returned windows.

The app intentionally does not consume rate-limit reset credits or expose conversation, configuration, or usage-changing methods. Its only authentication writes are explicit user-confirmed logout/login operations during desktop account switching.

## This Mac activity

The scanner discovers recent `.jsonl` files under `~/.codex/sessions` and `~/.codex/archived_sessions`. It uses local `/usr/bin/grep` prefiltering before strict decoding of only `turn_context` and `token_count` records. Candidate lines briefly enter process memory; only the latest bounded model ID, timestamps and numeric cumulative totals are retained. Each positive delta is attributed to the latest preceding model in physical record order. Per-rollout non-negative deltas ignore repeated counters, handle resets and deduplicate archived copies through stable rollout identity plus cumulative fingerprints.

The first seven-day scan is bounded to recently modified logs. Results are cached in memory for at least ten minutes. Scans run when Local Activity is opened, when the user manually refreshes, or periodically while the activity-chart menu mode is selected; quota checks remain on a separate two-minute schedule. No helper daemon remains running between scans.

## Cost estimates

`OpenAIPriceCatalog` is a dated, inspectable snapshot of standard per-million-token prices from official OpenAI model pages. Matching is exact by model ID; unknown models remain visibly unpriced unless the user supplies fallback rates. There is no runtime pricing request or external dependency.

`DisplayCurrency` converts the USD base estimate to USD, AUD or EUR using a dated ECB reference-rate snapshot. The selected app currency is a local preference; the CLI can optionally override the USD-to-selected-currency rate. No live FX request runs in the app.

The hypothetical model-price difference is intentionally an estimate: each known model's API-equivalent cost is compared with the same token usage priced as GPT-5.6 Sol. It appears only in the Estimates disclosure and is not presented as realized savings. Milestone banners are local-only UI state and are triggered at token, low-usage and reset-credit transitions. Banked resets come directly from `rateLimitResetCredits.availableCount`; the UI shows unavailable rather than inferring a value when that field is absent.

Cached input is a subset of input, so estimates price non-cached input as `input - cached`, then apply model-specific input, cached-input and output rates. Reasoning output is not added again because it is contained in output totals. Aggregate logs cannot reliably reveal request-level pricing adjustments such as long context, so the UI always calls the result an API-equivalent estimate rather than a bill.

## Distribution

Both the app and CLI are compiled for arm64 and x86_64 and merged into universal binaries. The free release is ad-hoc signed. WidgetKit is excluded until a Developer ID/App Group/notarization pipeline can preserve its capabilities reliably.
