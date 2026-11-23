# TubeFree — iOS YouTube client, no ad path

A native SwiftUI YouTube client for iOS 16+. It talks to YouTube's InnerTube
API directly and hands the resolved stream URL to `AVPlayer`. The watch page is
never loaded, so the ad stack is never instantiated — there is nothing to skip,
block or patch.

Not a wrapper, not a WKWebView, not a tweak. A real player.

## How the ad bypass works

| path | what happens |
|---|---|
| normal YouTube app | watch page loads → ad breaks requested → VAST/IMA plays pre-roll and mid-roll |
| this app | `POST /youtubei/v1/player` → `streamingData` → `AVPlayer(url:)` |

Ads are served by the *player page*, not by the media file. Ask the API for the
media file and the ad request never happens. Same reason NewPipe, Yattee and
every other third-party client has no ads: not blocked, just never invited.

## Client ladder

`InnerTube.playback()` walks three clients until one returns something playable:

1. **IOS** — returns `hlsManifestUrl`. Separate video/audio renditions, full
   resolution, AVPlayer handles quality switching itself. Preferred.
2. **ANDROID_VR** — returns direct progressive MP4 URLs (`itag 18/22/…`) with
   muxed audio. No PO token needed. Fallback when HLS is refused.
3. **WEB_EMBEDDED_PLAYER** — last resort after rate limiting.

Progressive formats carrying `signatureCipher` are skipped — there is no JS
interpreter on device to run the decipher transform, and shipping one is a
different project.

## Source layout

```
project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
.github/workflows/build.yml CI → unsigned .ipa artifact
Sources/
  TubeFreeApp.swift         entry, AVAudioSession category .playback
  Models.swift              Video, StreamFormat, PlaybackInfo, BenchError
  JSONX.swift               recursive JSON helpers + renderer walker
  InnerTube.swift           client profiles, request transport, player/search/browse
  Parse.swift               videoRenderer + lockupViewModel → [Video]
  FeedStore.swift           observable feed state
  HomeView.swift            feed, search, pull-to-refresh
  VideoRow.swift            thumbnail card
  PlayerScreen.swift        stream resolve, AVPlayerViewController, quality chips, up-next
  SettingsView.swift        HLS toggle, max progressive height, build info
```

## Build

The `.xcodeproj` is not committed — XcodeGen regenerates it, which is why the
repo stays diff-clean and CI never fights merge conflicts on a pbxproj.

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

- **TrollStore** (iOS 14.0–16.6.1 / 17.0, arm64e) — install the `.ipa` straight from Files.
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
- No login, so no subscriptions feed, no watch history, no personalized home.
  Search and trending only. Adding auth means OAuth device flow + cookie
  bridging, and Google rate-limits third-party sign-in aggressively.
- Progressive fallback tops out at 720p and only where itag 22 exists; HLS path
  is full resolution.
- Live streams play through HLS only.

## License

Source is yours. YouTube's ToS is YouTube's problem.
