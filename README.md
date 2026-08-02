# Clouds Background

Construct 3 effect addon for procedural drifting cloud backgrounds. It supports both WebGL and WebGPU and is intended for object or layer use.

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
