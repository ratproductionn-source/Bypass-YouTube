# TubeFree — iOS YouTube client, no ad path

A native SwiftUI YouTube client for iOS 16+. It talks to YouTube's InnerTube
API directly and hands the resolved stream URL to `AVPlayer`. The watch page is
never loaded, so the ad stack is never instantiated — there is nothing to skip,
block or patch.

Not a wrapper, not a WKWebView, not a tweak. A real player.

## How the ad bypass works

| path | what happens |
|---|---|
| stock YouTube app | watch page loads → ad breaks requested → VAST/IMA plays pre-roll and mid-roll |
| this app | `POST /youtubei/v1/player` → `streamingData` → `AVPlayer(url:)` |

Ads are served by the *player page*, not by the media file. Ask the API for the
media file and the ad request never happens. Same reason NewPipe, Yattee and
every other third-party client has no ads: not blocked, just never invited.

## Features

- **Feed** — trending/what-to-watch, pull to refresh
- **Search** — with live suggestions from the suggest endpoint
- **Watch screen** — AVPlayer with PiP, AirPlay, fullscreen, native scrub
- **Stream picker** — HLS auto or a specific progressive itag, switchable mid-play
- **Up next** — related videos, tap to swap the stream in place
- **Comments** — first page plus continuation paging
- **Details** — description, view count, publish date, length
- **Channels** — header, avatar, subscriber line, uploads grid, tap through
- **History** — local resume points, "continue watching" strip, progress bars, clearable
- **Settings** — HLS toggle, max progressive height, history management

No login, no cookies, no analytics, no tracking identifier. History lives in
`Application Support/history.json` and never leaves the device.

## Client ladder

`InnerTube.playback()` walks `Client.playbackLadder` until something plays:

1. **IOS** — returns `hlsManifestUrl`. Separate video/audio renditions, full
   resolution, AVPlayer handles quality switching itself. Preferred.
2. **ANDROID_VR** — returns direct progressive MP4 URLs (`itag 18/22/…`) with
   muxed audio. No PO token needed. Fallback when HLS is refused.
3. **WEB_EMBEDDED_PLAYER** — last resort after rate limiting.

The plain **ANDROID** client is used for `next` (comments, related) and channel
`browse`, but never for playback — it needs a PO token for media.

Progressive formats carrying `signatureCipher` are skipped: there is no JS
interpreter on device to run the decipher transform.

## Source layout

```
project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
.github/workflows/build.yml CI → unsigned .ipa artifact
push.sh                     repo create + push
Sources/
  TubeFreeApp.swift         entry, AVAudioSession category .playback
  Models.swift              Video, StreamFormat, PlaybackInfo, BenchError
  JSONX.swift               recursive JSON helpers + renderer walker
  InnerTube.swift           client profiles, transport, player/search/browse/next/suggest
  Parse.swift               video grids, lockup blocks, channel header, both comment shapes
  History.swift             local resume points, atomic JSON file
  FeedStore.swift           feed state
  HomeView.swift            feed, search, suggestions, continue watching
  VideoRow.swift            thumbnail card
  WatchScreen.swift         resolve, AVPlayerViewController, tabs, progress persistence
  ChannelScreen.swift       channel header + uploads
  SettingsView.swift        HLS toggle, max height, history
```

## Build

The `.xcodeproj` is not committed — XcodeGen regenerates it, which is why the
repo stays diff-clean and CI never fights merge conflicts on a pbxproj.

### GitHub Actions

`.github/workflows/build.yml` builds `TubeFree.ipa` on `macos-14` and uploads it
as an artifact. Trigger it with a push, a tag, or the Run workflow button.

`probe.yml` is a 5-second account health check. If probe is cancelled with zero
steps, GitHub is not scheduling jobs for the account — verify the email on the
account, set a spending limit, and retest before touching the build job.

### Codemagic (works when GitHub Actions will not schedule)

`codemagic.yaml` builds the same unsigned IPA on a Codemagic Mac. Add the repo at
https://codemagic.io/apps, pick the `ios-unsigned` workflow, start the build, and
the IPA appears under Artifacts. Free tier is ~500 macOS minutes a month.

Locally on macOS:

```bash
brew install xcodegen
xcodegen generate
open TubeFree.xcodeproj
```

On CI — push to `main`, or run the workflow manually:

```bash
gh workflow run build --repo <owner>/<repo>
gh run download --repo <owner>/<repo> -n TubeFree-ipa
```

Tag a release and the IPA lands on the Releases page:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

## Install

The IPA is unsigned, no developer account needed to produce it.

- **TrollStore** (iOS 14.0–16.6.1 / 17.0, arm64e) — install the `.ipa` from Files.
- **Sideloadly / AltStore / SideStore** — sign with a free Apple ID, 7-day resign.
- **Xcode** — set your own team, run on device directly.

For a personal device only, add your team to `project.yml`:

```yaml
    settings:
      base:
        DEVELOPMENT_TEAM: YOURTEAMID
        CODE_SIGNING_ALLOWED: YES
```

## Known limits

- `signatureCipher`-only formats are dropped. If AVPlayer gets a 403 on the HLS
  manifest, the ANDROID_VR progressive fallback usually carries it.
- No login, so no subscriptions feed, watch history from your account, likes,
  playlists or personalised home. Adding auth means OAuth device flow + cookie
  bridging, and Google rate-limits third-party sign-in aggressively.
- Progressive fallback tops out at 720p and only where itag 22 exists; the HLS
  path is full resolution.
- Comments come from the ANDROID client's `next` response; if Google stops
  returning the comment section there, the tab says so instead of guessing.
- Live streams play through HLS only.

## License

Source is yours. YouTube's ToS is YouTube's problem.
