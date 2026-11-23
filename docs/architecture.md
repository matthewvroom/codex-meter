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

Profiles are managed under **Settings → Accounts**. With multiple profiles, the header switcher changes the local app-server connection Meter uses to read quota. The desktop Codex app continues to use its existing sign-in.

The client performs the required `initialize` handshake before calling `account/rateLimits/read`. It prefers the `codex` entry in the multi-bucket response and falls back to the backward-compatible single-bucket response. Percentages are clamped to 0–100, and the menu bar displays the lowest remaining percentage across returned windows.

The app intentionally does not consume rate-limit reset credits or expose conversation, configuration, or usage-changing methods. Adding a profile is the only flow that starts an authentication operation.

## This Mac activity

The scanner discovers recent `.jsonl` files under `~/.codex/sessions` and `~/.codex/archived_sessions`. It filters lines in process and decodes only `turn_context` and `token_count` records. Only bounded model IDs, timestamps and numeric cumulative totals are retained from the records. Each positive delta is attributed to the latest preceding model in physical record order. Per-rollout non-negative deltas ignore repeated counters, handle resets and deduplicate archived copies through stable rollout identity plus cumulative fingerprints.

The seven-day scan uses recently modified logs and reads only the recent tail of large files. Each completed file is cached in memory. Reopening the popover resumes work by reusing unchanged files and reading new or changed files. The file in progress when a scan is canceled is retried. Scans also run on manual refresh and every ten minutes in activity-chart menu mode. Quota checks run on a separate two-minute schedule.

The activity overview marks the active profile’s observed credit resets at the end of the local day they occurred. The selected day’s hourly chart marks them at the recorded time. Meter identifies a reset from successive Codex quota responses that show a new weekly window and lower usage. The history starts with the first successful reading and skips ambiguous changes.

Milestone banners are local UI state triggered by token, low-usage and reset-credit transitions. Banked resets come directly from `rateLimitResetCredits.availableCount`. The UI shows the count as unavailable when that field is absent.

## CLI cost estimates

`OpenAIPriceCatalog` is a dated, inspectable snapshot of standard per-million-token prices from official OpenAI model pages. Matching is exact by model ID; unknown models remain visibly unpriced unless the user supplies fallback rates. There is no runtime pricing request or external dependency.

`DisplayCurrency` converts the USD base estimate to the currency passed to the CLI using a dated ECB reference-rate snapshot. The CLI accepts a USD-to-selected-currency rate override and performs conversion offline.

Cached input is a subset of input, so estimates price uncached input as `input - cached`, then apply model-specific input, cached-input and output rates. Output totals include reasoning tokens. The CLI labels the result an API-equivalent estimate because aggregate logs omit request-level pricing adjustments such as long context.

## Distribution

Both the app and CLI are compiled for arm64 and x86_64 and merged into universal binaries. The free release is ad-hoc signed. WidgetKit is excluded until a Developer ID/App Group/notarization pipeline can preserve its capabilities reliably.
