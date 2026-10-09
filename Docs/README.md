# AmbientDisplay

Full-screen ambient display for old iPhones: background video, a clock,
Metal shader effects, audio playback. Content ships as packages that are
pushed to the device or imported from a zip in the app.

## 1. Packages

`PackageManager` loads packages from `Documents/AmbientDisplay/Packages/` on
the device, not from the app bundle. Each package has a `manifest.json` with a
`type` of `theme` or `playlist`.

```json
{
  "packageId": "sample-scene-sunny",
  "type": "theme",
  "theme": {
    "displayName": "Sample Scene",
    "background": { "video": "test.mp4" },
    "weatherTags": ["day-sunny"],
    "layers": [ ... ]
  }
}
```

A playlist package has no theme section; its tracks live under `Playlist/`:

```json
{
  "packageId": "sample-playlist-package",
  "type": "playlist",
  "playlist": { "tracks": ["track1.mp3"] }
}
```

- Theme ID is derived as `packageId + ".theme"`, playlist ID as
  `packageId + ".playlist"`. Renaming a package changes it.
- Video and shaders live under the package's `Theme/` directory.
- `state.json` (same directory as `Packages/`) stores `activeThemeId`,
  `activePlaylistId` and `settings.weatherAutoTheme`.
- A playlist has no display name; the settings menu shows its `packageId`.

## 2. Layers

A theme is a video plus an ordered stack of layers. Layer 0 is at the bottom.
`AmbientThemeLayerCompositor` tears down and rebuilds the stack on every
theme switch (hard cut, no update in place).

| Kind | Renderer | Notes |
|---|---|---|
| `clock` | `AmbientClockLayerRenderer` | Native (`NSDateFormatter` + `UILabel`). |
| `effect` | `AmbientShaderEffectRenderer` | One generic Metal renderer for all visual effects. |

There is no `overlay` (HTML) kind. Shaders cannot do multi-line text layout.

## 3. Shaders

Shaders ship inside packages and are compiled at runtime
(`newLibraryWithSource:options:error:`). The only app-bundled shader code is
the shared fullscreen vertex function in `Rendering/Shaders/AmbientShaderCommon.metal`.
`AmbientShaderLibraryCache` pairs it with each package's fragment function.

### Effect layer manifest

```json
{
  "kind": "effect",
  "sensitivity": 1.0,
  "shaders": [
    {
      "path": "Shaders/Bars.metal",
      "inputs": ["audioLevels"],
      "params": { "x": 0.35, "y": 0.3, "z": 0.03, "w": 0.0 }
    }
  ]
}
```

- `path`: required, package-relative, containment-checked (no `..`, no absolute paths).
- `inputs`: optional named texture inputs (table below).
- `params`: optional, four floats whose meaning is defined by the shader.
- `sensitivity`: layer-level, clamped 0-10. Sent to every pass and used as audio gain.
- `shaders` is an ordered list of passes, ping-ponged between two textures, last
  pass to the drawable. Maximum `AmbientShaderMaxPassCount` (4).

### Fragment function

A shader file does not include headers. `AmbientShaderLibraryCache` prepends a
prelude (`kPackageShaderPrelude`, the canonical copy) that provides
`AmbientShaderUniforms` (`time`, `resolution`, `params`, `sensitivity`),
`VertexOut`, the binding indices and `ambient_hsv2rgb`.

```metal
fragment float4 fragment_mywash(VertexOut in [[stage_in]],
                                 constant AmbientShaderUniforms &uniforms [[buffer(AmbientShaderUniformBufferIndex)]]) {
    return float4(float3(in.uv, 0.5), 1.0);
}
```

Naming: `Shaders/MyWash.metal` must define `fragment_mywash` (`fragment_` + lowercased
basename, nothing else). A wrong name fails that layer only (logged).

### Inputs

| Name | Status |
|---|---|
| `previous` | Works. Unbound on pass 0. |
| `audioLevels` | Works. R32Float, width = bin count (default 64), height 1. All zeros if there is no audio source. |
| `original` | Reserved, not bound. |
| `sourceVideo` | Reserved, not bound. |
| package texture path | Not supported (see section 9). |

Audio is available to any effect pass. Smoothing (attack/release, resampling)
is native in `AmbientAudioLevelsTextureProvider`.

### Conventions

- `uv.y = 0` is the bottom of the screen, `uv.y = 1` is the top.
- Blending is standard alpha, configured by the app. Return `alpha = 0` to show lower layers.
- With no free `params` slot, a fixed opacity is a `static constant float` in the shader (see `GradientWash.metal`).
- Audio-reactive shaders should keep an idle floor that does not depend on the audio texture, so "not rendering" and "no signal" can be told apart (see `Bars.metal`, `params.z`).

## 4. Reference shaders

In `SamplePackages/sample-scene-*/Theme/Shaders/`.

| File | Inputs | params x / y / z / w |
|---|---|---|
| `GradientWash.metal` | none | hueA / hueB / angle (rad) / drift speed. Alpha fixed at 0.5. |
| `Bars.metal` | `audioLevels` | gapRatio (0-0.9) / cornerRadius (0-1) / idleFloor (0-1) / unused |
| `Waveform.metal` | `audioLevels` | minHalfHeight / hue / unused / unused |
| `RadialPulse.metal` | none | pulse speed / ring width / hue / max radius |
| `Particles.metal` | none | grid density / drift speed / hue / particle size |

## 5. Weather theme switching

Switches the active theme to match the weather at a user-set city.
Foreground only. No location permission and no Background Modes beyond audio.

**Flow**

1. `AmbientWeatherService` fetches the current WMO weather code and `is_day` from
   Open-Meteo (free, no key). Completion is delivered on the main queue.
2. `AmbientWeatherTags` maps the code to a condition and builds an ordered
   candidate list: `<period>-<condition>`, `<condition>`, `any`
   (for example `day-rainy`, `rainy`, `any`).
3. `AmbientWeatherThemeController` walks the list. The first tag carried by at
   least one installed theme decides. If several themes carry it, one is chosen
   at random. If the active theme already carries it, nothing changes.
   No match, a failed fetch, or a missing location keeps the current theme.
4. Switching calls `PackageManager setActiveThemeId:error:`. `ViewController`
   observes `activeThemeId` and rebuilds.

**Tags** are fixed in code, not user-editable. There are 19: six conditions
(`sunny cloudy foggy rainy snowy stormy`) each as `day-`, `night-` and
any-time, plus `any`. Authoring rules are in `Docs/WEATHER_TAGS.md`. At
launch, themes with an unknown tag log a warning.

| WMO codes | Condition |
|---|---|
| 0, 1 | sunny |
| 2, 3 | cloudy |
| 45, 48 | foggy |
| 51-67, 80-82 | rainy |
| 71-77, 85, 86 | snowy |
| 95-99 | stormy |
| anything else | cloudy |

**Controller behavior**

- Started by `AppDelegate`. Polls every 45 minutes (constant) and on
  `applicationDidBecomeActive:`.
- Acts only while `PackageManager.weatherAutoTheme` is YES. The property is
  observed, so turning it on evaluates the cached conditions and fetches fresh ones.
- Default for `weatherAutoTheme` is NO. Toggle it in the settings menu
  (section 10).

**Location:** `Documents/AmbientDisplay/weather-settings.json`, read on every poll.
Written with a Cleveland, Ohio placeholder if missing. Choose a city in the
settings menu, which overwrites the `location` entry (other keys are kept)
and triggers an immediate refresh.

```json
{ "location": { "name": "Cleveland, Ohio", "latitude": 41.4993, "longitude": -81.6944 } }
```

**Tests:** `Scripts/weather_test.sh [lat lon]` builds the tag and service code
on macOS, checks the code-to-tag mapping, and runs one live fetch.

## 6. File map

```
AmbientDisplay/
├── App/            AppDelegate (owns audio engine and weather controller,
│                   settings long-press, open-in-zip handler), main
├── Audio/          AudioEngineManager
├── Packages/       PackageManager (themes, playlists, state.json)
├── Settings/       AmbientSettingsViewController, AmbientLocationPickerViewController,
│                   AmbientLocationStore, AmbientPackageImporter, AmbientZipExtractor
├── ViewController  Background video, observes activeThemeId and installedThemes
├── Weather/
│   ├── AmbientWeatherConditions     Raw conditions (WMO code, isDay)
│   ├── AmbientWeatherService        Open-Meteo client
│   ├── AmbientWeatherTags           Fixed tag vocabulary and mapping
│   └── AmbientWeatherThemeController  Polling, location, switching
└── Rendering/
    ├── Core/       AmbientAudioDataSource, AmbientThemeLayerCompositor, AmbientThemeLayerRenderer
    ├── Effects/    AmbientShaderTypes, AmbientShaderRecipe, AmbientShaderLibraryCache,
    │               AmbientAudioLevelsTextureProvider, AmbientTextureCache (UIImage only)
    ├── Renderers/  AmbientClockLayerRenderer, AmbientShaderEffectRenderer
    └── Shaders/    AmbientShaderCommon.metal

SamplePackages/     sample-playlist-package, sample-scene-sunny, sample-scene-rainy, sample-scene-cloudy
Scripts/            push_package.sh, container_path.sh, deployDebug.sh, deployProd.sh,
                    weather_test.sh/.m
Docs/               README.md, WEATHER_TAGS.md
entitlements.plist  Used to ad-hoc sign the IPA (jailbroken devices)
dist/               deployProd.sh output (AmbientDisplay-<version>.ipa), not committed
```

## 7. Keep in sync by hand

`AmbientShaderUniforms` exists in three places:

1. `AmbientShaderTypes.h` (source of truth).
2. `AmbientShaderCommon.metal` (includes 1, no drift possible).
3. `kPackageShaderPrelude` in `AmbientShaderLibraryCache.m` (string literal copy;
   `VertexOut` is duplicated here too).

On any change, update in that order. Nothing checks that 1 and 3 match.

`AmbientShaderTypes.h` is included from both Objective-C and Metal source, so
it may only use types that mean the same in both (simd types; no ObjC classes,
no Metal-only keywords).

## 8. Gotchas

- **Edits to `SamplePackages/` do nothing on a device** until pushed with
  `Scripts/push_package.sh <path>` or imported as a zip. The script uses
  `rsync -avzi` and does not delete packages removed from the repo; remove
  those on the device by hand.
- **Packages load at launch and after an in-app import.** A package pushed with
  `push_package.sh` still needs a force-quit and relaunch (backgrounding is
  not relaunching).
- **`state.json` pins the active theme** across launches. It only falls back to
  the first installed theme if `activeThemeId` is unset or not installed. If a
  pushed package seems ignored, check `state.json` first. It also holds
  `weatherAutoTheme`.
- **Manifest shape matters.** `themeFromDict:` silently drops themes that do not
  match the schema in section 1. Import runs the same parser first and rejects
  a package that would be dropped.
- **Metal include path:** `AmbientShaderCommon.metal` must use
  `#include "../Effects/AmbientShaderTypes.h"`. Header Search Paths do not
  reliably apply to the Metal frontend.
- **Uninstalling deletes the packages.** The app's `Documents/` goes with it,
  including `Packages/`, `state.json` and `weather-settings.json`.
  `deployProd.sh` never uninstalls; `deployDebug.sh` falls back to it.
- **Device access:** over a USB tunnel (`iproxy 2222 22`), SSH is
  `ssh -p 2222 root@localhost` and scp uses `-P 2222`. The app container path
  changes on reinstall; `find /var/mobile/Containers/Data/Application -maxdepth 4 -type d -path '*Documents/AmbientDisplay'`.
- **Document type registration is cached by iOS.** After changing
  `CFBundleDocumentTypes` in `Info.plist`, delete and reinstall the app or
  "Open in AmbientDisplay" may not appear.
- **`libcompression`** is needed by the zip extractor. Newer Xcode auto-links it;
  if the link fails with `_compression_stream_init`, add `libcompression.tbd`
  under Link Binary With Libraries.

## 9. Open items

- **Package textures:** `AmbientTextureCache` returns `UIImage`; passes need `MTLTexture`.
- **`original` and `sourceVideo` inputs:** nothing binds a texture yet.
- **Audio texture provider** is per renderer; two audio layers duplicate the work.
- **Shader compilation** is synchronous.
- **Shader security** is an assumption (worst case is GPU cost), not verified.
  Confirm before loading third-party packages. Zip import makes this more
  relevant, since anyone can now hand the app a package.
- **Prelude duplication** (section 7) has no automated check.
- **Package management:** no way to delete a package from the UI; playlists have
  no display name.
- **Zip import:** no zip64, encryption or symlinks; CRC32 is not verified.
  Replacing the *active playlist* in place does not restart audio until it is
  reselected or the app relaunches (`AudioEngineManager` only reacts to
  `activePlaylistId` changing).
- **Weather:** day/night changes can lag up to about an hour (45 minute poll plus
  Open-Meteo's 15 minute update step). No wind condition (not in WMO codes).

## 10. Settings menu

Long-press anywhere on the screen for about a second. A modal
`AmbientSettingsViewController` opens with four sections:

| Section | What it does |
|---|---|
| Weather | "Match theme to weather" switch (`PackageManager.weatherAutoTheme`), and a location row that opens a city search (Open-Meteo geocoding, no key). |
| Theme | Installed themes with a checkmark on the active one. Selectable only while weather matching is off, so a manual pick can never fight the controller. |
| Music | Installed playlists (shown by `packageId`); picking one calls `setActivePlaylistId:error:`. |
| Packages | "Import Package (.zip)…" opens the system file picker. |

The table observes `PackageManager`, so checkmarks follow theme changes made by
the weather controller while the screen is open.

### Importing a package

Two ways in, same pipeline (`AmbientPackageImporter`):

- **From the settings menu:** the file picker, for a zip saved somewhere Files can see.
- **Open in AmbientDisplay:** AirDrop or any share sheet (Filza too) lists the
  app for `.zip` files. `AppDelegate application:openURL:options:` imports it
  and shows the result alert. This is the easier route on iOS 12, where saving
  an AirDropped zip to Files is unreliable. Needs the `CFBundleDocumentTypes`
  entry in `Info.plist` (`public.zip-archive`, `com.pkware.zip-archive`).

Import steps:

1. Extract to a staging directory in `tmp` (`AmbientZipExtractor`). Rejects
   `..` and absolute paths, backslashes, symlinks, encrypted and zip64 archives,
   more than 4096 entries or 1.5 GB extracted. Skips `__MACOSX`, `.DS_Store`, `._*`.
2. Find `manifest.json` at the zip root, or inside exactly one top-level folder
   (what Finder's Compress produces).
3. Validate by running the real `PackageManager` parser on a throwaway instance.
   A package that would not load (bad manifest, missing video or tracks) is
   rejected before it touches `Packages/`.
4. Require a safe `packageId` (`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`).
5. Install into `Packages/<packageId>`. If a package with the same `packageId`
   is already installed (matched by manifest, not folder name) it is replaced.
6. Reload `PackageManager` on the main queue. `ViewController` observes
   `installedThemes`, so a replaced active theme reloads immediately.

## 11. Building and releasing

```bash
Scripts/deployDebug.sh               # Debug build, install; falls back to uninstall+install
Scripts/deployProd.sh                # Release build, dist/AmbientDisplay-<version>.ipa, install
Scripts/deployProd.sh --no-install   # Release IPA only (for a GitHub release)
```

Both scripts build with `CODE_SIGNING_ALLOWED=NO`, ad-hoc sign with
`entitlements.plist`, and zip a `Payload/` into an IPA. This only installs on
jailbroken devices (via `ideviceinstaller`). `deployProd.sh` reads the version
from the built app, so bump `MARKETING_VERSION` (and the build number) in Xcode
before releasing.

Releasing, from a clean working tree on the release branch:

```bash
Scripts/deployProd.sh --no-install
git tag -a v1.0 -m "AmbientDisplay 1.0"
git push origin HEAD --follow-tags
gh release create v1.0 dist/AmbientDisplay-1.0.ipa \
    --title "AmbientDisplay 1.0" --notes-file RELEASE_NOTES_1.0.md
```
