# Privacy

Codex Meter is designed so useful monitoring does not require another monitoring service.

## What the app reads

- Current rate-limit data through the local, read-only Codex app-server interface.
- Model IDs from `turn_context` records and aggregate `token_count` events in recently modified files under `~/.codex/sessions` and `~/.codex/archived_sessions`.
- Local preferences for alert thresholds, display mode, currency, custom fallback rates and launch at login.
- Account profile directories created under `~/.codex-meter/accounts`; Codex owns their credentials and Codex Meter never reads them.

## What the app deliberately ignores

Rollout logs can contain private prompts, responses, tool calls and file paths. The history scanner uses a local filter to reduce candidate lines, then decodes narrow structures containing only the exact event discriminator, bounded model ID, timestamp and numeric token totals. Candidate lines exist briefly in process memory, but unknown fields are never retained in models, logs, history or errors.

## What leaves the Mac

Codex Meter has no analytics, telemetry, advertising, account service or history upload. The quota request is handled by the installed Codex process using its existing session. Local history, model pricing and USD/AUD/EUR conversion do not make network calls.

When automatic update checks are enabled, the app makes up to two unauthenticated HTTPS requests per day to GitHub's public Releases API: one for the original project and one for Matthew's fork. These requests contain no Codex credentials, account information, prompts, responses, token history or usage totals. Automatic checks can be disabled in Settings. Codex Meter never downloads or installs an update without the user opening its GitHub release page.

Adding an account starts the supported `codex login` browser flow with a profile-specific `CODEX_HOME`. Email, password, SSO and MFA are entered only on OpenAI's secure page; the browser returns the completed session directly to Codex. Codex Meter then starts the read-only app-server under that profile. The app does not copy, parse or display `auth.json`, access tokens, passwords or verification codes.

Deleting a non-default profile requires confirmation and removes its entire local `CODEX_HOME`, including the Codex-owned cached credentials. It does not delete or modify the OpenAI account. If the folder is already absent, Codex Meter still removes the stale profile entry.

Choosing **Meter + Codex** is an explicit authentication change. Codex Meter closes the desktop app, asks Codex app-server to log out the default profile, and starts OpenAI's supported ChatGPT browser login. The browser and Codex exchange the credentials directly; Meter only receives the documented success state and account email used to verify that the intended profile was selected. Passwords, SSO secrets, MFA codes, access tokens and `auth.json` contents are never read or copied by Meter.

The banked-reset number is OpenAI's reported `availableCount`, not a local estimate. Codex Meter displays it but never calls the reset-credit consumption method.

## Cost estimates

ChatGPT subscriptions are not billed as a simple per-token API invoice. Codex Meter therefore does not claim to show money spent. It applies a bundled, dated snapshot of official standard API prices entirely offline. Custom fallback rates for unknown models remain in local preferences. No local usage is sent to OpenAI's pricing pages.
