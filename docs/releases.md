# GitHub Releases

## Public downloads

This repository is configured to publish public release assets through GitHub Releases:

- `VO_NVDA_Remote.dmg`
- `VO_NVDA_Remote.zip`
- `appcast.xml` on GitHub Pages

## Triggering a release

Push a tag like:

```bash
git tag v0.1.0
git push origin v0.1.0
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

If those secrets are absent, the workflow still publishes unsigned public release assets and an appcast.

## Appcast URL

The workflow publishes:

```text
https://peetchy.github.io/VoiceOverNVDARemote/appcast.xml
```

If the repository owner or repository name changes, update the `APPCAST_URL` in `.github/workflows/release.yml`.
