# Contributing to Codex Meter

Thanks for wanting to make Codex Meter better.

## Before you start

- Search the existing issues before opening a new one.
- Keep changes focused. Small pull requests are easier to review and ship.
- Never include Codex credentials, raw app-server traffic, or private account data in issues, tests, or logs.

## Local setup

You need macOS 13 or newer, Swift 6, and a working Codex installation.

```sh
git clone https://github.com/matthewvroom/codex-meter.git
cd codex-meter
SKIP_LIVE_CODEX_CHECK=1 ./scripts/test.sh
./scripts/build-app.sh
```

To run the live integration check, sign in to Codex and run `./scripts/test.sh` without `SKIP_LIVE_CODEX_CHECK`.

## Pull requests

1. Explain the problem and why the change is needed.
2. Add or update checks for behaviour changes.
3. Run the parser checks and a clean build.
4. Update the README or `/docs` when behaviour changes.

By contributing, you agree that your contribution is licensed under the MIT License.
