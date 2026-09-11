# AmbientDisplay
# AmbientDisplay Architecture

This document reflects the current architecture plan. The original diagram
(single WKWebView pipeline with a bridge pushing time/weather/track/audioBins
into visual.js) is legacy and no longer describes the system.

## Overview

The rendering pipeline is built around a compositor that owns a stack of
independently swappable layer renderers, plus one fixed background video
layer underneath everything.

## Core Pieces

### AmbientThemeLayerCompositor
Owned by ViewController. A single `loadTheme:` call tears down the current
layer stack and rebuilds it from scratch. Layer order in the theme's
`layers` array determines z-order.

### Background video
`AmbientTheme.backgroundVideoURL` is rendered as a fixed base layer,
underneath the layer stack. It is not a layer kind and does not go through
the renderer factory. Every theme has exactly one video base.

### AmbientThemeLayerRendererFactory
The only place that maps a layer's `kind` string to a concrete renderer
class. Returns nil for unrecognized kinds, so older manifests do not crash
on newer builds and vice versa.

### AmbientThemeRenderContext
The shared dependency bundle passed to every renderer the same way (theme
directory, audio source, texture cache), even if a given renderer ignores
most of it.

### Renderer kinds
- **Visualizer** - privileged, audio-only
- **Recipe** - particles, gradientWash, radialPulse, spriteAnimation, or custom
- **Clock** - native, keeps ticking even with JS disabled
- **Overlay** - locked-down WKWebView, one of four layer kinds now, not the
  whole presentation surface

### AmbientEffectRecipe / AmbientEffectRecipeLoader / AmbientTextureCache
The places where package-supplied data is actually validated and clamped.
Shared by any effect that needs them.

## Audio data

`AudioEngineManager` already conforms to what a visualizer renderer needs.
No new protocol methods are required, just adding conformance:

```objc
@interface AudioEngineManager : NSObject <AmbientAudioDataSource>
```

```objc
@protocol AmbientAudioDataSource <NSObject>
@property (nonatomic, readonly) NSUInteger spectrumBinCount;
@property (atomic, copy, readonly, nullable) NSArray<NSNumber *> *latestSpectrumBins;
@end
```

This is pull-based, not a per-frame delegate callback. Bin count is
queryable via `spectrumBinCount`, not assumed to be a fixed 32.