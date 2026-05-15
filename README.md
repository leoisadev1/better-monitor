# Better Monitor

Better Monitor is a native macOS system monitor built with SwiftUI and AppKit. It is meant to feel familiar if you use Activity Monitor, while staying table-first, fast to launch, and lighter on the default refresh path.

It is still an unsigned local build, not a notarized App Store app. The install script below builds it from source, ad-hoc signs it, installs it, and removes macOS quarantine from this app bundle so it opens normally.

## Install

```sh
git clone https://github.com/leoisadev1/better-monitor.git
cd better-monitor
scripts/install-better-monitor.sh
```

That installs `Better Monitor.app` into `/Applications` and opens it.

If you do not want to use `sudo`, install into your user Applications folder:

```sh
scripts/install-better-monitor.sh --user
```

If macOS still blocks the app, run:

```sh
xattr -dr com.apple.quarantine "/Applications/Better Monitor.app"
open "/Applications/Better Monitor.app"
```

For a user install, use:

```sh
xattr -dr com.apple.quarantine "$HOME/Applications/Better Monitor.app"
open "$HOME/Applications/Better Monitor.app"
```

After the app is installed from a GitHub release, future releases can be installed from **Better Monitor > Check for Updates...**. The updater uses Sparkle and the signed `appcast.xml` asset attached to the latest GitHub release.

## What It Does

- CPU, Memory, Energy, Disk, Network, and Cache panes in a persistent left sidebar.
- Native AppKit process table with process icons, search, scope filters, sortable columns, and per-pane column defaults.
- Pane sidebar metrics load in the background, so Memory, Disk, Energy, and Network are not blank until clicked.
- Search keeps the table usable. If a search has no live matches, the app falls back to the full process list instead of leaving an empty screen.
- Quit and Force Quit actions have confirmation dialogs and verify whether the process actually exited.
- Two-finger/right-click process rows expose Quit and Force Quit.
- Open Location, Inspect, and Open Files actions are intentionally lightweight and lazy so the main process refresh does not crawl every executable path or file descriptor.
- Dock/Finder app icon is bundled from `Resources/AppIcon.icns`.

## Build And Run

```sh
swift build
swift run better-monitor
```

Package a standalone app bundle:

```sh
scripts/package-better-monitor.sh
open "dist/Better Monitor.app"
```

Install the packaged app:

```sh
scripts/install-better-monitor.sh
```

## Release Workflow

Pushing to `main` runs `.github/workflows/release.yml`.

The workflow:

- resolves the next patch version from existing `v*` tags, or uses `VERSION` for the first release,
- runs `swift test`,
- runs the sampler performance gate,
- builds `Better Monitor.app`,
- embeds Sparkle,
- creates `dist/Better-Monitor-<version>.zip`,
- signs the zip for Sparkle,
- writes `dist/appcast.xml`,
- verifies the app bundle signature,
- creates a GitHub release with the zip and appcast attached.

Manual releases can be started from GitHub Actions with a specific version.

The Sparkle public key is committed through the package script. The private key must stay secret and is expected in the GitHub repository secret named `SPARKLE_PRIVATE_KEY`.

To test release artifacts locally:

```sh
APP_VERSION=0.1.0 BUILD_NUMBER=1 TAG_NAME=v0.1.0 scripts/make-release-artifacts.sh
```

If you need to regenerate the Sparkle key:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account better-monitor
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account better-monitor -x private-key.txt
gh secret set SPARKLE_PRIVATE_KEY < private-key.txt
rm private-key.txt
```

## Validate

```sh
swift test
scripts/probe-sampler.sh
xcodebuild -scheme better-monitor -destination 'platform=macOS' build
```

`scripts/probe-sampler.sh` runs the live sampler through the test target without launching Better Monitor or Activity Monitor. It fails if average sampling time or probe RSS exceed the configured budgets.

## Performance Notes

Better Monitor avoids expensive work on the default refresh path:

- Process identity comes from `sysctl(KERN_PROC_ALL)` plus libproc task info.
- Memory summaries use Mach/sysctl APIs instead of spawning `vm_stat`.
- Disk summaries use IOKit storage counters instead of spawning `iostat`.
- Network summaries use `getifaddrs` instead of spawning `netstat`.
- Energy summaries use IOKit power APIs instead of spawning `pmset`.
- Per-process network enrichment is only collected for the Network pane.
- Per-process sleep assertions and wakeups are only collected for Energy-related views.
- Open files and ports are loaded only when you ask for them.

## Requirements

- macOS 14 or newer
- Xcode command line tools or Xcode
- Swift 6.3 toolchain
- GitHub CLI only if you want to publish or manage the repo from the terminal
- `SPARKLE_PRIVATE_KEY` GitHub secret for automatic one-click update releases

## Uninstall

```sh
rm -rf "/Applications/Better Monitor.app"
```

or, for a user install:

```sh
rm -rf "$HOME/Applications/Better Monitor.app"
```

## Status

This is a local developer build. It is ad-hoc signed and not notarized. For broad public distribution, the next real step is Developer ID signing and notarization so users do not need quarantine removal.
