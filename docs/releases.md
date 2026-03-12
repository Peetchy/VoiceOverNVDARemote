# GitHub Releases

## Public downloads

This repository is configured to publish public release assets through GitHub Releases:

- `VO_NVDA_Remote.dmg`
- `appcast.xml` on GitHub Pages
- older GitHub releases are removed when a new release is published

## Triggering a release

Push a tag like:

```bash
git tag v0.1.1
git push origin v0.1.1
```

Or run the `Release` workflow manually from GitHub Actions using `workflow_dispatch`.

## Required repository settings

Enable GitHub Pages:

- Source: `Deploy from a branch`
- Branch: `gh-pages`
- Folder: `/ (root)`

## Optional secrets

If you want signed and notarized public releases, add these repository secrets:

- `CODESIGN_IDENTITY`
- `APPLE_ID`
- `TEAM_ID`
- `APP_PASSWORD`
- `SPARKLE_PRIVATE_ED_KEY`

Add this repository variable for in-app Sparkle verification:

- `SPARKLE_PUBLIC_ED_KEY`

If those secrets are absent, the workflow still publishes unsigned public release assets and an appcast.
Those unsigned assets are useful for internal testing, but macOS Gatekeeper on a different machine may still block them until you add Developer ID signing and notarization secrets.

## Xcode project

The repository now includes an Xcode app project generated from [project.yml](/Users/itsawatbanlawanich/projects/vo-remote-desktop/vo-nvda-remote/project.yml). Use:

```bash
./scripts/generate_xcode_project.sh
./scripts/archive_xcode_app.sh
```

If you want `xcodebuild` to ask Apple for signing assets, run:

```bash
ALLOW_PROVISIONING_UPDATES=1 ./scripts/archive_xcode_app.sh
```

On this machine, command-line automatic signing is still blocked because `xcodebuild` reports `No Account for Team "9P4236SF25"` even though the source project and unsigned archive path now work.

## Appcast URL

The workflow publishes:

```text
https://peetchy.github.io/VoiceOverNVDARemote/appcast.xml
```

If the repository owner or repository name changes, update the `APPCAST_URL` in `.github/workflows/release.yml`.
