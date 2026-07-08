# Clouds Background

Construct 3 effect addon for procedural drifting cloud backgrounds. It supports both WebGL and WebGPU and is intended for object or layer use.

## Addon ID

`sgtconti_clouds_background`

## Features

- Procedural cloud field; no texture dependency.
- Adjustable opacity, density, scale, wind, drift, bob, contrast, softness, sky tint and seed.
- Optional transparent-area masking.
- Uses layout-space coordinates so the cloud field follows layer scrolling.

## Parameters

| Parameter | Description |
|---|---|
| Opacity | Cloud overlay opacity. |
| Density | Cloud coverage. |
| Scale | Cloud feature scale. |
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
