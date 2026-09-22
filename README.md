# Clouds Background

Construct 3 effect addon for procedural drifting cloud backgrounds. It supports both WebGL and WebGPU and is intended for object or layer use.

## Install

Download [`dist/sgtconti_clouds_background-1.3.0.0.c3addon`](dist/sgtconti_clouds_background-1.3.0.0.c3addon)
(use the **Download raw file** button), then in Construct 3 open *Menu → View →
Addon Manager → Install new addon* and pick the file. Reload the editor when prompted.

Tagged builds are also attached to [Releases](../../releases), and every push
produces the same package as a CI artifact under the
[Package c3addon workflow](../../actions/workflows/package.yml).

## Addon ID

`sgtconti_clouds_background`

## Features

- Four cloud types from one shader: cumulus, altostratus, cirrus and cumulonimbus.
- Procedural cloud field; no texture dependency.
- Adjustable opacity, density, scale, wind, drift, bob, contrast, softness, sky tint and seed.
- Optional transparent-area masking.
- Uses layout-space coordinates so the cloud field follows layer scrolling.
- The procedural cloud core and Scale response are restored from the original working version.

## Cloud types

Set with the **Cloud type** parameter. Every other parameter still applies; each type
just interprets the shared cloud field differently.

| Value | Type | Look |
|---|---|---|
| `0` | Cumulus | Broken puffs over open sky. The original effect, unchanged. |
| `1` | Altostratus | Closed grey overcast sheet in wide flat layers, no defined edges. |
| `2` | Cirrus | Sparse fibrous streaks high in the frame, stretched along the wind. |
| `3` | Cumulonimbus | Tall billowing storm mass with a lit crown, anvil top and dark base. |

Values in between are rounded to the nearest type. Because `Cloud type` selects a
different shape, it is not interpolatable — animate `Opacity` or `Density` to blend
between weather states instead.

## Parameters

| Parameter | Description |
|---|---|
| Opacity | Cloud overlay opacity. |
| Density | Cloud coverage. For altostratus the sheet always covers the sky, so it sets light transmission instead. |
| Scale | Cloud coordinate scale using the original version's behavior. |
| Wind X | Horizontal drift speed in pixels per second. |
| Wind Y | Vertical drift speed in pixels per second. |
| Drift | Internal cloud evolution speed. |
| Bob | Small sinusoidal vertical bob amount. |
| Contrast | Cloud definition. |
| Softness | Softness of cloud edges. |
| Sky tint | How much the sky gradient tints the clouds. |
| Sky top color | Top color of the sky gradient. |
| Sky bottom color | Bottom color of the sky gradient. |
| Only on transparent | `0` renders the full rectangle. `100` renders only where the foreground layer/object is transparent. |
| Seed | Offsets the random pattern. |
| Cloud type | `0` cumulus, `1` altostratus, `2` cirrus, `3` cumulonimbus. |
| Horizon | Perspective toward a horizon line. `0` keeps the flat field. |
| Horizon line | Where the horizon sits, as a percentage down the view. |

## Horizon

By default the cloud field is orthographic: a cloud is the same size at the top of
the view as it is at the bottom. **Horizon** adds perspective, treating the field as
a flat deck seen from below. A row lower in the view looks further along that deck,
so it samples further into the field: the pattern compresses vertically, spreads out
from the view centre horizontally, and — because the wind is still applied in field
space afterwards — distant clouds drift across the screen more slowly than overhead
ones. **Horizon line** places the vanishing row, which matters when terrain covers
the lower part of the view.

Two details are deliberate. The compression is capped at about 6x: true perspective
is `1/(1-t)`, whose slope grows much faster than the curve itself, and left uncapped
a single screen row near the horizon spans hundreds of layout px, far above the pixel
rate — the far field turns to sparkle. Haze is then blended in toward the horizon,
which is what a receding deck looks like anyway and which collapses the contrast of
whatever detail does survive the compression.

At `Horizon` 0 the field is byte-for-byte what it was before the parameter existed.

## Performance notes

The cost of this effect is dominated by `noise()` evaluations per pixel. All four
types share a single noise pipeline, so adding types did not add per-pixel work:

| Cloud type | `noise()` per pixel | Relative cost |
|---|---|---|
| Cumulus (`0`) | 32 | 1.00x (identical to the previous version) |
| Altostratus (`1`) | 19 | ~0.65x |
| Cirrus (`2`) | 19 | ~0.65x |
| Cumulonimbus (`3`) | 32 | ~1.05x |

Altostratus and cirrus have no billowing interior to describe, so they skip the
fine-detail noise pair entirely.

The shader also returns early when its output cannot be seen — `Opacity` at 0, or
`Only on transparent` at 100 over opaque pixels — which skips the whole cloud field
for those pixels.

To reduce cost further in a project: lower `Scale` (fewer, larger cloud features
alias less), or place the effect on a layer that is not redrawn every frame.

## Renderer consistency

`effect.fx` derives the field coordinate from Construct's source-rect and layout
uniforms. Construct does not populate all of them on every render path, so both
rectangles are checked before use and fall back when they arrive degenerate.

Guarding a divide with `max(span, vec2(1e-6))` does not help here: it scales the
coordinate by a million rather than falling back, so consecutive pixels land
thousands of noise cells apart, every pixel hashes as its own cell, and the clouds
collapse into single-pixel static. `effect.wgsl` was never affected because it uses
Construct's own `c3_getLayoutPos()`, so WebGPU rendered correctly while WebGL did
not — which is why this surfaced on Linux, where the WebGL path is the common one.

## Driver consistency

The cloud field is generated from a permutation hash whose intermediates all stay
inside the range a 32-bit float represents exactly, and whose `sin`/`cos` calls
only ever see arguments in `[0, 2pi)`. That matters because the wind offset grows
without bound as a layout runs, so the older `fract(sin(dot(p, k)) * 43758.5453)`
hash ended up feeding `sin()` arguments of 1e5 immediately and 1e7 within an hour.
GPU drivers range-reduce `sin()` very differently at that magnitude — some
collapse it to a handful of values, which showed up on some Linux/Mesa systems as
a static, repeating pattern with no cloud structure.

The field is now bit-identical on every driver and on both renderers, and it no
longer degrades however long a layout runs. The trade-off is that it repeats every
289 lattice cells — roughly 150,000 layout px at the default `Scale`, far beyond
what is visible on screen.
