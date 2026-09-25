# AmbientDisplay — Architecture & Refactor Notes

This documents the shader-based rendering refactor (Sept 2026): the
finished architecture, how to author a shader-based effect for a
package, and what's still open. Supersedes the earlier "stub" version
of this doc from partway through the refactor. Meant to replace/merge
into `Docs/README.md`.

---

## 1. Core architecture

**Layer system.** A theme is a background video plus an ordered stack of
"layers" (`AmbientTheme.layers`, array of `AmbientThemeLayer`). Layer 0
renders first (bottom, directly above the video); later entries stack on
top. `AmbientThemeLayerCompositor` owns this stack — tear down and
rebuild from scratch on every theme switch, no update-in-place (same
hard-cut philosophy as playlist/video switching elsewhere in the app).

**Exactly two layer kinds, by design:**
- `"kind": "clock"` → `AmbientClockLayerRenderer` — native. Text
  rendering (`NSDateFormatter` + `UILabel`) is the one thing that can't
  reasonably move to a shader, and it's the cheapest possible
  implementation performance-wise, which matters on the old phones this
  targets.
- `"kind": "effect"` → `AmbientShaderEffectRenderer` — everything else.
  One generic Metal renderer for all visual effects: gradients,
  particles, audio visualizers, whatever comes next. No per-effect
  native classes.

**`"kind": "overlay"` was dropped entirely**, not kept as a third kind —
it rendered package-supplied HTML/CSS in a locked-down `WKWebView`,
which was both the heaviest thing the app could instantiate per layer
and inconsistent with keeping everything else as cheap as possible.
Shaders + package textures cover most of what it was used for. The one
real gap this leaves: shaders can't do proper multi-line text layout. If
a theme ever needs a paragraph of styled text as a layer, that's the
case this decision doesn't cover.

## 2. Shader model

**Shaders ship inside packages, not the app bundle** — including the
app's own default effects (`SamplePackages/sample-scene-package/Theme/Shaders/`
is treated exactly like a third-party package would be). Metal compiles
`.metal` source at runtime (`newLibraryWithSource:options:error:`), so a
package is pure data (manifest + shader source + assets) with nothing
prebuilt for a specific OS/GPU.

**One exception, on purpose:** the shared fullscreen-quad **vertex**
function lives in the app bundle (`Rendering/Shaders/AmbientShaderCommon.metal`,
compiled into the app's default `MTLLibrary` at build time). Every pass
in every recipe uses this same vertex function — only the fragment
function varies per effect, and that's always the runtime-compiled,
package-supplied part. `AmbientShaderLibraryCache` pairs the app's
precompiled vertex function with each package's runtime-compiled
fragment function when building a pipeline state.

**Multi-pass support.** An effect layer's `"shaders"` array is an
ordered stack of passes (`AmbientShaderPass` / `AmbientShaderRecipe`),
ping-ponged between two intermediate `MTLTexture`s by
`AmbientShaderEffectRenderer`, with the last pass writing to the
drawable. A pass declares named texture inputs it wants (`"previous"`,
`"original"`, `"audioLevels"`, `"sourceVideo"`, or eventually a package
texture path) rather than assuming a fixed pipeline position. Capped at
`AmbientShaderMaxPassCount` (4) — see `AmbientShaderTypes.h`.

**Audio reactivity is not a privileged built-in.** Any pass in any
effect layer can declare `"audioLevels"` as an input and get it — there
is no longer a single hardcoded class that's the only one allowed to see
audio data. `AmbientThemeLayerRendererFactory` passes the same context,
audio source included, to every renderer; `AmbientClockLayerRenderer`
just never reads it. The audio smoothing itself
(`AmbientAudioLevelsTextureProvider`) stays native — attack/release
envelope, resample to a fixed canonical bin count (default 64) — because
that's "feel," not visuals, and every shader author would otherwise
have to reimplement an envelope filter correctly. It writes into an
`R32Float` texture that shaders sample directly.

## 3. Hooking into shaders — writing an effect layer

This is the part a theme/package author (first-party or third-party)
actually needs. An effect layer looks like this in `manifest.json`:

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

- **`path`** — required, package-relative, resolved and containment-checked
  the same way `AmbientTextureCache` resolves texture paths (no `..`, no
  absolute paths, must resolve inside the theme's directory). `.metal`
  source or a precompiled `.metallib`.
- **`inputs`** — optional array of named texture inputs this pass wants
  bound (see the table below). Omit for a pass that's a pure function of
  time + params.
- **`params`** — optional; four floats, `x`/`y`/`z`/`w`, meaning defined
  entirely by the shader itself (see `AmbientShaderEffectRenderer.m`'s
  `AmbientParamsDictToFloat4`). There's no schema beyond that — this is
  intentionally the same "generic knobs" contract for every effect.
- **`sensitivity`** — a layer-level (not per-pass) param, read from the
  effect layer's own parameters, clamped to 0–10, passed to every pass's
  uniforms *and* used as the audio provider's gain when the layer wants
  `audioLevels`.
- **`"shaders"` is an array** — multiple entries means multiple
  ping-ponged passes (see §2). Most effects are a single pass.

### Writing the fragment function itself

A package `.metal` file does **not** need `#include <metal_stdlib>` /
`using namespace metal;` / the uniform or vertex-output struct
declarations, or the binding-index constants — `AmbientShaderLibraryCache`
prepends a shared prelude to every package shader's source before
compiling it (see "the prelude," below). Just write the fragment
function:

```metal
fragment float4 fragment_mywash(VertexOut in [[stage_in]],
                                 constant AmbientShaderUniforms &uniforms [[buffer(AmbientShaderUniformBufferIndex)]]) {
    float3 color = float3(in.uv, 0.5);
    return float4(color, 1.0);
}
```

**Naming convention:** a file `Shaders/MyWash.metal` must define exactly
one fragment function named `fragment_mywash` — `"fragment_"` +
the file's basename, **lowercased, no other transformation** (so
`GradientWash.metal` → `fragment_gradientwash`, not
`fragment_gradient_wash`). `AmbientShaderLibraryCache` derives this name
mechanically from the path; get it wrong and the layer fails to build
(logged, that one layer just doesn't render — it won't crash the app).

**What's available in every fragment function**, via the prelude
(`AmbientShaderLibraryCache.m`'s `kPackageShaderPrelude` — this is the
canonical copy if these ever look out of sync with this doc):

```metal
struct AmbientShaderUniforms {
    float time;                // seconds since -start, not wall clock
    float2 resolution;         // current drawable size, points
    float4 params;             // this pass's params dict -> (x, y, z, w)
    float sensitivity;         // layer's "sensitivity" param, 0...10
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

#define AmbientShaderUniformBufferIndex     0
#define AmbientShaderTexturePreviousIndex   0
#define AmbientShaderTextureOriginalIndex   1
#define AmbientShaderTextureAudioLevelsIndex 2
#define AmbientShaderTextureSourceVideoIndex 3

float3 ambient_hsv2rgb(float3 hsv); // hue/sat/val (0...1 each) -> linear RGB
```

**Named inputs table** — what you can put in a pass's `"inputs"` array,
and what actually happens if you do:

| Name | Bound to | Status |
|---|---|---|
| `"previous"` | This layer's own prior-pass output texture | Works. Unbound (nil) on pass 0 — check before sampling, or just don't declare it on pass 0. |
| `"audioLevels"` | `AmbientAudioLevelsTextureProvider`'s texture — width = bar/bin count, sample with `texture.get_width()` if you need it, height 1 | Works. If the theme's audio source is nil, you get an all-zero texture, not a crash. |
| `"original"` | Reserved — the layer's pre-effect source content | **Not wired up.** Declaring it is harmless (silently left unbound) but samples undefined/empty. |
| `"sourceVideo"` | Reserved — the background video's current frame | **Not wired up**, same as above. |
| a package texture path | `AmbientTextureCache`-resolved image | **Not wired up** — `AmbientTextureCache` returns `UIImage`, shader passes need `MTLTexture`, nothing bridges the two yet. |

### The uv coordinate system — read this before writing a shader

**`uv.y = 0` is the bottom of the screen, `uv.y = 1` is the top.** Metal's
NDC y-axis points up, and that carries through unchanged into this
project's fullscreen-triangle uv mapping (`AmbientShaderCommon.metal`).
This is easy to get backwards (an earlier draft of `Bars.metal` did
exactly that, anchoring bars at the top and growing them downward
instead of the intended bottom-up equalizer look) — if you're writing
anything direction-sensitive (bars, a horizon line, "grows upward"),
double check against this before assuming.

### Alpha and compositing

Effect layers composite over the background video and every layer below
them with standard alpha blending (set up once in
`AmbientShaderLibraryCache`'s pipeline descriptor — a package shader
doesn't need to configure blending itself, just return the alpha it
wants). Return `alpha = 0` anywhere you want lower layers to show
through. If your params vector is already fully spoken for and you still
want a tunable opacity, the established pattern (see `GradientWash.metal`)
is a hand-tunable `static constant float` at the top of the file — not
ideal (not manifest-configurable), but there's no free params slot
convention beyond the four floats, and that's a deliberate constraint,
not an oversight.

### A debugging pattern worth keeping: the idle floor

`Bars.metal` has an `idleFloor` param (`params.z`) that guarantees a
faint minimum bar height even at silence. This isn't just a visual
nicety — it's how we diagnosed a real bring-up bug: "the visualizer
shows nothing" is ambiguous between *the layer isn't rendering at all*
(build/binding failure) and *it's rendering correctly but there's no
audio signal reaching it* (transparent-at-silence is correct behavior).
An idle floor that's independent of the audio texture turns that
ambiguity into a direct visual test. Worth the same treatment in any
future audio-reactive shader.

## 4. The reference shaders

All five ship in `SamplePackages/sample-scene-package/Theme/Shaders/`.
None of them are literal ports of the pre-refactor native primitives —
the old parameter sets lived in `AmbientEffectRecipeLoader.m`, which was
deleted and never re-uploaded during this refactor, so these define
fresh, equivalent parameter sets rather than guessing at the old exact
numbers.

| File | Fragment fn | Inputs | params.x / y / z / w |
|---|---|---|---|
| `GradientWash.metal` | `fragment_gradientwash` | none | hueA / hueB / angle (rad) / drift speed. Alpha is the hardcoded `kWashAlpha` constant (0.5), not a param — see "Alpha and compositing" above. |
| `Bars.metal` | `fragment_bars` | `audioLevels` | gapRatio (0–0.9) / cornerRadius as a fraction of bar half-width (0–1) / idleFloor (0–1) / unused |
| `Waveform.metal` | `fragment_waveform` | `audioLevels` | minHalfHeight (uv units) / hue (0–1) / unused / unused |
| `RadialPulse.metal` | `fragment_radialpulse` | none (declared none on purpose — see file comment on whether audio-triggered pulses are worth it later) | pulse speed / ring width (uv units) / hue / max radius (uv units, aspect-corrected) |
| `Particles.metal` | `fragment_particles` | none | grid density (cells/axis) / drift speed / hue / particle size (fraction of a cell) |

`Particles.metal` in particular is a genuine redesign, not a port — the
old primitive was `CAEmitterLayer`-based, and there's no direct
translation of that cell/birth-rate/velocity model to a fragment shader.
What's there instead is a hash-noise procedural field (3×3 neighborhood
per pixel, one soft dot per grid cell, twinkling/drifting via
`uniforms.time`).

Only `GradientWash` and `Bars` are wired into the sample manifest today.
`Waveform`/`RadialPulse`/`Particles` are implemented and ready — add a
third `"effect"` layer entry to use any of them.

## 5. Current file map

```
Rendering/
├── Core/
│   ├── AmbientAudioDataSource.h              Protocol; doc updated to reflect audio is no longer privileged
│   ├── AmbientThemeLayerCompositor.h/.m      Unchanged by this refactor
│   └── AmbientThemeLayerRenderer.h/.m        Two-kind dispatch (clock / effect), no privilege stripping
├── Effects/
│   ├── AmbientTextureCache.h/.m              Unchanged — still image-only (UIImage), not yet MTLTexture-bridged
│   ├── AmbientShaderTypes.h                  Uniform struct + binding-index constants + max pass count — shared source of truth for the ObjC/app-bundle-Metal side
│   ├── AmbientShaderRecipe.h/.m              Manifest "shaders" array -> AmbientShaderPass objects
│   ├── AmbientShaderLibraryCache.h/.m        Compiles/caches pipeline states; owns the package-shader prelude (see §3)
│   └── AmbientAudioLevelsTextureProvider.h/.m Resample + attack/release smoothing -> R32Float texture
├── Renderers/
│   ├── AmbientClockLayerRenderer.h/.m        Unchanged
│   └── AmbientShaderEffectRenderer.h/.m      The one generic effect renderer — build + multi-pass draw loop
└── Shaders/
    └── AmbientShaderCommon.metal             App-bundled shared vertex function; #includes ../Effects/AmbientShaderTypes.h

SamplePackages/
├── sample-playlist-package/
│   └── manifest.json
└── sample-scene-package/
    ├── manifest.json                         Real schema now (type/theme wrapper, background.video) — see §6 gotcha
    └── Theme/
        ├── test.mp4
        └── Shaders/
            ├── Bars.metal
            ├── Waveform.metal
            ├── Particles.metal
            ├── GradientWash.metal
            └── RadialPulse.metal
```

**Deleted, superseded:** `AmbientEffectRecipe.h/.m`,
`AmbientRecipeEffectRenderer.h/.m`, `AmbientVisualizerEffectRenderer.h/.m`,
`AmbientOverlayLayerRenderer.h/.m`, `SamplePackages/sample-scene-package/Theme/index.html`.

## 6. Known duplication — keep these in sync by hand

`AmbientShaderUniforms` exists in **three** places, not two:

1. `AmbientShaderTypes.h` — the ObjC-visible source of truth.
2. `AmbientShaderCommon.metal` — `#include`s (1) directly, so this one's
   free (no drift possible here).
3. `AmbientShaderLibraryCache.m`'s `kPackageShaderPrelude` — a **hand-written
   string literal duplicate**, because a package `.metal` file is
   compiled standalone at runtime from just its own text, with no
   build-system `#include` resolution available for a package's sibling
   files. `VertexOut` is duplicated here too (it isn't in
   `AmbientShaderTypes.h` at all, since it has no ObjC-side meaning).

Nothing enforces (1) and (3) stay identical. If you ever add a field to
`AmbientShaderUniforms` or a new binding-index constant, update all
three, in this order: `AmbientShaderTypes.h` → `AmbientShaderCommon.metal`
(free, via the include) → `kPackageShaderPrelude` in
`AmbientShaderLibraryCache.m` (manual).

## 7. Operational gotchas found during bring-up

These cost real debugging time getting the refactor's clock+visualizer
working end to end on-device — worth documenting so the next person
doesn't repeat the same loop:

- **`PackageManager` reads from `Documents/AmbientDisplay/Packages/` at
  runtime, not the app bundle.** Editing `SamplePackages/` in the Xcode
  project changes nothing on a running device until you actually push it
  there (`Scripts/push_package.sh <path>`) and reload. `git diff`-ing the
  repo tells you nothing about what a running install is actually doing.
- **`state.json`'s `activeThemeId` persists across launches and silently
  pins whatever theme was last active** — including a leftover test
  package from before this refactor even started. If a freshly-pushed,
  verified-correct package still doesn't seem to load, check
  `Documents/AmbientDisplay/state.json` on-device before suspecting the
  push or the code: `resolveActiveThemeWithFallback` only falls back to
  `installedThemes.firstObject` when `activeThemeId` is unset or points
  at nothing installed — it will happily keep loading a stale theme
  forever otherwise, silently and without any log distinguishing that
  from "your new package failed to parse."
- **Backgrounding the app is not relaunching it.** `reloadInstalledPackages`
  only runs from `application:didFinishLaunchingWithOptions:`. A pushed
  package update won't be picked up by bringing the app back to the
  foreground — fully force-quit it first.
- `push_package.sh` now runs with `rsync -avzi` (itemize) instead of
  plain `-avz`, so a push actually lists which files it decided differ,
  rather than only printing directory names and leaving "did it actually
  transfer the changed file" ambiguous.
- The original `manifest.json` scaffold for `sample-scene-package` used
  a flat, pre-refactor schema (`themeId`/`backgroundVideoURL` at the top
  level) that `PackageManager.m`'s `themeFromDict:` never actually
  parses — it silently dropped the whole theme rather than erroring
  loudly. The real expected shape is `{"packageId", "type": "theme",
  "theme": {"displayName", "background": {"video": ...}, "weatherTags",
  "layers"}}`. `themeId` isn't a manifest field at all — `PackageManager`
  derives it as `packageId + ".theme"`.
- `AmbientShaderCommon.metal` lives in `Rendering/Shaders/`, but
  `AmbientShaderTypes.h` lives in `Rendering/Effects/` — a bare quoted
  `#include "AmbientShaderTypes.h"` only auto-resolves against files in
  the *same* directory as the includer, and this project's Header Search
  Paths don't reliably cover it for the Metal compiler frontend even
  though they do for clang. Use the relative path,
  `#include "../Effects/AmbientShaderTypes.h"`.

## 8. What's left / open

- **Package-declared textures aren't bridged.** `AmbientTextureCache`
  returns `UIImage`; shader passes need `MTLTexture`. Needs either an
  `MTLTexture`-returning accessor on `AmbientTextureCache` (via
  `MTKTextureLoader`) or an adapter in `AmbientShaderEffectRenderer`.
  Blocks any package shader that wants to sample an image asset.
- **`"original"` and `"sourceVideo"` inputs are reserved slots only** —
  nothing binds a texture there yet. Needs the background video's
  current frame piped into `AmbientThemeRenderContext`.
- **`AmbientAudioLevelsTextureProvider` is per-renderer, not shared.**
  Two audio-reactive layers in one theme each resample/smooth
  independently rather than sharing one pass. A real optimization,
  deferred because sharing it means widening `AmbientThemeRenderContext`'s
  contract (and touching `AmbientThemeLayerCompositor`), not just this
  one class.
- **Shader compilation is synchronous.** Fine for the current theme-switch
  frequency; revisit if theme-switch stutter is ever actually observed
  with a heavier shader.
- **Package shader compile security is a stated assumption, not
  verified**: believed threat model is GPU workload cost / DoS via a
  pathological shader, nothing worse, since Metal source has no
  filesystem/network/syscall access. Worth independent confirmation
  before any non-first-party package is ever loaded in production.
- **The `AmbientShaderUniforms` triplication in §6** — no automated check
  keeps the hand-written prelude string in `AmbientShaderLibraryCache.m`
  in sync with `AmbientShaderTypes.h`.
- **Weather-based theme switching** — see §9, entirely unbuilt still.

## 9. Planned, not yet built: weather-based theme switching

Unchanged since before this refactor — the data model already
half-expects this (`PackageManager.weatherAutoTheme` and
`-randomThemeMatchingWeatherTag:` exist, `AmbientTheme.weatherTags` is
already populated by manifests), but nothing calls a weather API yet.

**Planned location — new top-level module, peer of `Audio/`:**

```
AmbientDisplay/
└── Weather/
    ├── AmbientLocationProvider.h/.m         CoreLocation wrapper → lat/lon
    ├── AmbientWeatherService.h/.m           Calls api.weather.gov → maps to a weatherTag string
    └── AmbientWeatherThemeController.h/.m   Polls on a timer, calls PackageManager
```

- **`AmbientLocationProvider`** — thin `CLLocationManager` wrapper,
  requests when-in-use authorization, returns lat/lon or nil.
- **`AmbientWeatherService`** — targets `api.weather.gov` (free, no key,
  requires a `User-Agent` header). Two-step call: `/points/{lat},{lon}`
  to resolve the forecast grid, then `/gridpoints/.../forecast`. Map
  from NWS's forecast **icon** codes, not the free-text description —
  more reliable against a fixed `weatherTags` vocabulary.
- **`AmbientWeatherThemeController`** — timer-driven (30–60 min interval).
  On a successful fetch, if `weatherAutoTheme` is on, resolve a matching
  theme via `-randomThemeMatchingWeatherTag:` and switch via
  `-setActiveThemeId:error:`. A failed fetch skips that cycle silently —
  never disrupt the currently showing theme.

**Lifecycle:** owned/started by `AppDelegate`, same pattern as
`AudioEngineManager` — kick off in
`application:didFinishLaunchingWithOptions:` (or
`applicationDidBecomeActive:` for foreground-only polling).

**Also needed, outside `Weather/`:**
- `Info.plist` — add `NSLocationWhenInUseUsageDescription`.
- `entitlements.plist` — only if weather should be checked while
  backgrounded (`Background Modes` capability). Foreground-only polling
  is simpler and probably sufficient for an always-running ambient
  display — decide explicitly rather than defaulting into it.

*(Not yet scaffolded as files — this section is the plan only.)*
