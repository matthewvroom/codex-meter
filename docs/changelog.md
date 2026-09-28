# Changelog

## 1.6.8

- Recover from an app-server initialization timeout without leaving future usage refreshes stuck.
- Cover a timed-out first handshake followed by a successful retry in the deterministic app-server test.
- Resolve universal build products through Swift so packaging works with newer toolchains.

## 1.6.7

- Prevent a retiring Codex helper's delayed disconnect callback from clearing the replacement helper's live connection.
- Stabilize automatic recovery after transient app-server timeouts and Codex restarts.

## 1.6.6

- Restart and retry the Codex usage helper once after a timeout or unexpected disconnect.
- Keep the last successful menu-bar badge visible while usage is stale or a refresh is recovering.
- Explain stale and failed refreshes in the badge tooltip instead of replacing the reading with an empty indicator.

## 1.6.5

- Corrected oversized-log accounting so inherited cumulative counters are used as baselines instead of new activity.
- Clarified that local API-equivalent pricing is an estimate, not a ChatGPT or Codex bill.
- Closed the menu-bar popover reliably when Codex Meter loses focus.
- Added selectable update channels for the original project and Matthew's fork using GitHub's public Releases API.
- Preserved an existing `/Applications/Utilities` installation location during source installs.

## 1.6.4 — 2026-08-24

- Fit the popover to its visible content and cap it to the current screen before enabling one scrolling body.
- Clear unsolicited first-responder highlights when the popover opens and make in-app notices dismissible.
- Trigger low-usage alerts only on a threshold crossing for the selected limiting window.
- Separate Reset + Percentage from Reset + Percentage + Pace, make the pace variant the fresh-install default and capitalize mode names.
- Move refresh time beside the refresh control and keep the full plan name beneath the app title.
- Rename Local Activity to This Mac Activity, bound long scans, make zero and tiny days visible, and clarify that estimates are not subscription charges.
- Refresh bundled GPT-5.6 standard API prices from the official model pages and leave unknown models unpriced in the app.

## 1.6.3 — 2026-08-21

- Refine the borderless badge typography and add a symmetric, one-pixel center pace marker with a knockout through the rail.

## 1.6.2 — 2026-08-21

- Remove the filled weekly badge capsule and render its countdown, percentage and pace marks directly as adaptive template elements.

## 1.6.1 — 2026-08-21

- Render the compact weekly badge with a Retina bitmap, wider insets and more breathing room.
- Prevent the account picker from taking focus whenever the popover opens.
- Clarify pace summaries with `usage is ...` phrasing.
- Summarize oversized local session logs so Local Activity remains responsive on very large Codex histories.

## 1.6.0 — 2026-08-21

- Added a knockout weekly badge combining reset countdown, remaining percentage and pace.
- Added a shared weekly pace model with a progressive `−50%` to `+50%` scale and human-readable time translation.
- Added expanded pace details, usage-bar ticks and explicit remaining-percentage labeling.
- Capped oversized popovers with scrolling while preserving natural height for compact states.
- Compact Local Activity now shows the top four models first and keeps long costs on one line.
- Moved API-equivalent comparisons into a clearly labelled Estimates disclosure and removed hypothetical savings from the menu bar and celebrations.
- Changed local session-log scanning to run on demand unless the activity-chart menu mode needs periodic updates.

## 1.5.4 — 2026-08-18

- Prefer the current native Codex app helper over older Homebrew and npm launchers.
- Supply GUI-launched helper processes with Homebrew and local binary paths so script-based fallbacks can find Node.
- Added deterministic coverage for helper selection order after Codex or macOS updates.

## 1.5.3 — 2026-08-17

- Increased the countdown numerals for easier at-a-glance reading while keeping the `d` and `h` suffixes compact.

## 1.5.2 — 2026-08-17

- Added a Reset + percentage menu-bar mode with a compact stacked days-and-hours countdown.
- Kept the countdown and adjacent percentage tied to the same most-constrained usage window.
- Added exact local reset details to the menu-bar tooltip and accessibility label.
- Added deterministic countdown formatting and tied-window selection checks.

## 1.5.1 — 2026-08-17

- Made the existing default Codex/ChatGPT profile the stable zero-setup account and migrated earlier random default-profile identifiers.
- Fixed successful default-profile refreshes clearing stale optional-login errors.
- Added protocol-stage diagnostics and a Copy Diagnostics action for usage failures.
- Replaced Add Account's silent CLI subprocess with the supported app-server browser-login flow.
- Kept optional profiles Meter-only and removed the inherited path that could sign the main Codex app out.
- Made the exact local reset date and time visible beside the relative reset countdown.
- Added a deterministic fake app-server integration check that enforces initialize-response ordering before `account/rateLimits/read`.
- Added a live windowed QA launch mode for testing the same view used by the menu-bar popover.

## 1.5.0 — 2026-07-15

- Moved the named account switcher beside refresh with an explicit down-arrow affordance.
- Added a confirmation choice for Meter-only or Meter plus Codex desktop switching.
- Implemented desktop switching with OpenAI's documented app-server logout, secure browser login, account verification and relaunch flow.
- Fixed Codex opening with the supported settings deep link plus bundle-ID and application-path fallbacks.
- Fixed deletion for stale account records whose local profile directory is already missing.
- Added visible banked-reset counts from OpenAI's authoritative `rateLimitResetCredits.availableCount` field, with an honest unavailable state.
- Added live account-read, reset-history and profile-deletion validation.

## 1.4.0 — 2026-07-15

- Added confirmed deletion of unused local account profiles and their Codex-owned credentials.
- Clarified the boundary between meter profiles and the separately authenticated Codex desktop app.
- Added an in-app handoff to open Codex for desktop account switching.

## 1.3.2 — 2026-07-15

- Changed Add Account to the normal OpenAI browser sign-in flow so email, password, SSO and MFA stay on OpenAI's page.
- Isolated each saved account with file-scoped Codex credentials and activated it only after successful login.

## 1.3.1 — 2026-07-15

- Clarified USD, AUD and EUR symbols in model costs, savings and CLI output.
- Restored the translucent liquid-glass surface, material section depth and restrained native motion.

## 1.2.0 — 2026-07-15

- Added local token attribution by the model recorded for each Codex turn.
- Added model-by-model token totals, shares and API-equivalent estimates in the popover and CLI.
- Added persistent USD, AUD and EUR display currencies plus CLI exchange-rate overrides.
- Added automatic standard pricing for locally observed GPT-5.4, GPT-5.5 and GPT-5.6 model families from official OpenAI model pages.
- Added explicit price-source dating, unknown-model handling and custom fallback rates.
- Bumped history JSON to schema version 2 with structured pricing metadata.
- Expanded model-switch, duplicate-log, counter-reset, unknown-model and pricing coverage.

## 1.3.0 — 2026-07-15

- Added isolated `CODEX_HOME` account profiles with supported device-login flow and one-click hot swap.
- Added collapsible usage, local-activity and settings sections.
- Added menu-bar savings total and in-app milestone banners for savings, tokens, low usage and banked resets.

## 1.1.0 — 2026-07-15

- Added privacy-safe seven-day token activity history from local Codex session logs.
- Added a compact native activity chart in the popover.
- Added optional API-equivalent cost estimates with user-owned rates.
- Added four configurable menu-bar display modes.
- Added the universal `codex-meter` CLI with JSON, history and threshold exit codes.
- Added explicit privacy documentation and the production WidgetKit signing roadmap.
- Expanded honest-error, inspectability, low-footprint and zero-dependency product positioning.

## 1.0.0 — 2026-07-15

- Added native menu-bar usage display.
- Added primary and secondary Codex usage windows with local reset times.
- Added configurable low-usage notifications and launch-at-login support.
- Added resilient multi-bucket response parsing and unit coverage.
- Added universal Apple silicon and Intel packaging.
- Added open-source community, security, CI, and release documentation.
