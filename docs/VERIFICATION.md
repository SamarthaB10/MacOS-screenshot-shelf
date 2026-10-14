# Verification

## Commands

- `cargo fmt --check`: passed.
- `MACOSX_DEPLOYMENT_TARGET=26.0 cargo check`: passed during implementation.
- `cargo clippy --all-targets -- -D warnings`: passed after pointer safety documentation was added.
- `./scripts/build-app.sh`: passed. Builds, signs, and verifies a temporary app bundle, then creates a ZIP without resource forks or extended attributes.
- `Screenshot Shelf --status`: reports `/Users/samarthab/screenshots:rec`, matching the configured macOS screenshot folder. The first native path bridge failed this check and was fixed by retaining C-owned path bytes.
- `codesign --verify --deep --strict`: passed on the staged bundle. The synced working-folder bundle acquires Finder metadata after creation and can fail strict bundle verification. The download ZIP is created before that metadata is added.
- GitHub build workflow: introduced in the download PR; current run results are reported in the chat and PR checks.

No unit or integration tests were written or run, as requested. There was no existing test suite.

## Live checks

- A generated image with screenshot metadata entered pending storage and opened the widget. Existing general images were left untouched.
- The user confirmed that a drag into ChatGPT works after transfer staging was added.
- The user confirmed that direct capture works after permission approval and app restart.
- Shortcut approval requires Accessibility and Screen Recording access. The app must remain running.
- Independent checks for full-screen apps, a second monitor, timeout over a complete 10-minute period, and very large images remain unverified.
- Exact preview latency and peak memory are not yet measured. Single RSS samples are not peak-memory results.

## Size and resource observations

The final local app bundle is about 412 KB; the ZIP is about 179 KB. These values exclude screenshots and native macOS frameworks. Process samples showed 0% CPU while idle. RSS changed across launch, permission prompts, and widget use, so the 30 MB idle and 80 MB widget targets are not yet confirmed.

## Review

The first standards review found repeated expiry error alerts. The first requirements review found a non-atomic idle deadline and selection of the oldest image after restart. The fixes add delayed retries and a single active alert, atomic deadline replacement, and restoration of the newest image. A final review checks the full app change against the first main commit.

## External use

GitHub was used for source pushes, pull requests, and build checks. Apple documentation and browser source code were read for API facts. No database, production data, or deployment was used. The app stores screenshots locally and has no app network client; a receiving app performs its own upload.
