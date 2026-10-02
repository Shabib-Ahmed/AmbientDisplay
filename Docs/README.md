# AmbientDisplay

Full-screen ambient display for old iPhones: background video, a clock,
Metal shader effects, audio playback. Content ships as packages that are
pushed to the device.

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

- Theme ID is derived as `packageId + ".theme"`. Renaming a package changes it.
- Video and shaders live under the package's `Theme/` directory.
- `state.json` (same directory as `Packages/`) stores `activeThemeId`,
  `activePlaylistId` and `settings.weatherAutoTheme`.

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
| package texture path | Not supported (see section 8). |

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
Foreground only. No location permission and no Background Modes.

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
- Default for `weatherAutoTheme` is NO. There is no UI to change it yet; edit `state.json`.

**Location:** `Documents/AmbientDisplay/weather-settings.json`, read on every poll.
Written with a Cleveland, Ohio placeholder if missing, never overwritten.

```json
{ "location": { "name": "Cleveland, Ohio", "latitude": 41.4993, "longitude": -81.6944 } }
```

**Debug:** in DEBUG builds, tapping the screen toggles between `day-sunny` and
`day-rainy`. The first tap suspends real polling until relaunch.

**Tests:** `Scripts/weather_test.sh [lat lon]` builds the tag and service code
on macOS, checks the code-to-tag mapping, and runs one live fetch.

## 6. File map

```
AmbientDisplay/
├── App/            AppDelegate (owns audio engine and weather controller), main
├── Audio/          AudioEngineManager
├── Packages/       PackageManager (themes, playlists, state.json)
├── ViewController  Background video, observes activeThemeId
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

SamplePackages/     sample-playlist-package, sample-scene-sunny, sample-scene-rainy
Scripts/            push_package.sh, container_path.sh, deployDebug.sh, weather_test.sh/.m
Docs/               README.md, WEATHER_TAGS.md
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
  `Scripts/push_package.sh <path>`. The script uses `rsync -avzi` and does not
  delete packages removed from the repo; remove those on the device by hand.
- **Packages load only at launch.** Backgrounding is not relaunching; force-quit.
- **`state.json` pins the active theme** across launches. It only falls back to
  the first installed theme if `activeThemeId` is unset or not installed. If a
  pushed package seems ignored, check `state.json` first. It also holds
  `weatherAutoTheme`.
- **Manifest shape matters.** `themeFromDict:` silently drops themes that do not
  match the schema in section 1.
- **Metal include path:** `AmbientShaderCommon.metal` must use
  `#include "../Effects/AmbientShaderTypes.h"`. Header Search Paths do not
  reliably apply to the Metal frontend.
- **Device access:** over a USB tunnel (`iproxy 2222 22`), SSH is
  `ssh -p 2222 root@localhost` and scp uses `-P 2222`. The app container path
  changes on reinstall; `find /var/mobile/Containers/Data/Application -maxdepth 4 -type d -path '*Documents/AmbientDisplay'`.

## 9. Open items

- **Package textures:** `AmbientTextureCache` returns `UIImage`; passes need `MTLTexture`.
- **`original` and `sourceVideo` inputs:** nothing binds a texture yet.
- **Audio texture provider** is per renderer; two audio layers duplicate the work.
- **Shader compilation** is synchronous.
- **Shader security** is an assumption (worst case is GPU cost), not verified.
  Confirm before loading third-party packages.
- **Prelude duplication** (section 7) has no automated check.
- **Settings menu:** not built. Needs the weather toggle, city picker, theme list
  and package import (source, format, validation, live reload). Manual theme
  selection must set `weatherAutoTheme = NO`.
- **Weather:** day/night changes can lag up to about an hour (45 minute poll plus
  Open-Meteo's 15 minute update step). No wind condition (not in WMO codes).
