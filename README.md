# PlotterGraph

Generative line art with a live-adjustable GUI, built as a single [Processing](https://processing.org/) sketch. Designed for pen plotters: everything exports as clean, millimetre-accurate SVG.

![PlotterGraph GUI with a spirograph and superformula on two pen layers](docs/screenshot.png)

## Features

- **30 patterns** — flow field, wave lines, spirograph, noise rings, Lissajous, contour map, Truchet tiles, hatch shading, strange attractor, superformula, nested polygons, spiral, moire circles, circle packing, harmonograph, Hilbert curve, sunburst, maze, L-system, guilloche, Maurer rose, phyllotaxis, subdivision, warped grid, fractal tree, Voronoi, image, hex Truchet, Penrose, hex maze.
  - **Maze** — recursive-backtracker maze drawn as walls or as its centre-line path (same seed on two layers = walls + solution-style path in a second pen). Wall segments are merged into long strokes to minimise pen lifts.
  - **L-system** — Koch snowflake, dragon curve, Gosper curve, Sierpinski arrowhead and a branching plant, with angle tweak, jitter and smoothing.
  - **Guilloche** — banknote-style rosettes: interleaved lines oscillating between two lobed envelopes.
  - **Maurer rose** — straight chords stepping around a rose curve; optional rose outline and extra copies with a shifted step.
  - **Phyllotaxis** — golden-angle sunflower layout drawn as circles, radial dashes or the Fibonacci spiral families.
  - **Subdivision** — recursive rectangle splits, cells filled with serpentine (single-stroke) hatching, cross-hatching or concentric squares.
  - **Warped grid** — op-art line grid bent by lens bulges (or pinches) and optional noise.
  - **Fractal tree** — recursive branches with angle/length randomness and bend; each branch continues the parent stroke.
  - **Voronoi** — Lloyd-relaxed cells with shared borders drawn once, plus optional smoothed inset rings ("pebbles").
  - **Image** — turn a photo (PNG/JPG/GIF) into a single-stroke TSP line, stipple dots, tone-based cross-hatching, a wiggling spiral or squiggle lines. Contrast, brightness and invert controls; without a photo a built-in demo picture is used.
  - **Hex Truchet** — hexagonal Truchet tiles with arcs, mixed straight/arc tiles or a random mix; strokes are joined across tiles.
  - **Penrose** — P3 rhomb tiling by Robinson-triangle subdivision, drawn as rhombs, as matching arcs (closed loops) or both.
  - **Hex maze** — recursive-backtracker maze on a hexagon grid, as walls or centre-line path, with optional loops.
- **Up to 4 pen layers** — each with its own pattern, seed, parameters, pen colour, pen width, scale/rotate/offset transform and mask. Combine patterns, or plot each layer with a different pen.
- **Live preview** — drag sliders, pick paper size (A5/A4/A3/Square, portrait or landscape), and see the result update immediately.
- **Undo / redo** — every parameter change (a whole slider drag counts as one step), up to 200 steps.
- **Parameter locks** — right-click a pattern parameter or the seed to lock it; Randomize, New seed and batch export leave locked values alone.
- **Masks** — keep a layer only inside or outside a shape: typed text (use `|` for a new line) or a loaded PNG/JPG/GIF/SVG silhouette, with threshold and invert.
- **Plot time estimate** — pen-down distance, pen-up travel and number of pen lifts per layer, turned into a plot time from your plotter's speeds.
- **Path clean-up** — simplification (Ramer-Douglas-Peucker), joining paths whose ends nearly touch, dropping tiny fragments and duplicate paths, and nearest-neighbour travel optimisation. The preview, statistics and export all use the cleaned-up paths.
- **Registration marks and pen test swatches** — optional corner crosshairs drawn by every pen (to line the paper up after a pen change) and a small test patch per pen, plotted first, in the bottom margin.
- **Export** — SVG (real paper size in millimetres, one Inkscape layer per pen), G-code (GRBL-style, Z-axis or servo pen lift) or HPGL; optionally one file per pen.
- **Batch export** — write a series of variations (seed +1, +2, …) in one go into `exports/batch_<timestamp>/`.
- **Presets** — save and load the full setup (paper, output settings, mask, all 4 layers including locks) as JSON. A handful of example presets are included in [`GenerativeLineArt/presets`](GenerativeLineArt/presets).

## Running it

Open [`GenerativeLineArt/GenerativeLineArt.pde`](GenerativeLineArt/GenerativeLineArt.pde) in the [Processing IDE](https://processing.org/download) (4.x) and press Run. No extra libraries are required.

## Controls

- **Design / Output tabs** at the top of the panel: *Design* holds the paper, layers and pattern parameters; *Output* holds the plotter speeds and time estimate, path clean-up, registration marks / pen test, mask source, export format and batch export.
- **Sliders / dials** in the left panel adjust the current layer's parameters live. Mouse wheel over a slider = fine adjustment; elsewhere in the panel it scrolls.
- **Right-click** a pattern parameter or the seed to lock / unlock it (a padlock appears next to its name).
- **Layer tabs** (1–4) switch which pen layer you're editing.
- **Pattern dropdown** picks the pattern for the current layer; Left/Right arrow keys cycle through patterns.
- **New seed / Randomize / Reset** buttons (or `N`/`Space`, `R`) regenerate the current layer.
- **Undo / Redo** buttons, or `Ctrl+Z` and `Ctrl+Y` / `Ctrl+Shift+Z` (`Cmd` on macOS).
- **Mask** (Design tab, per layer): Off / Inside / Outside. Pick the text or image on the Output tab.
- **Export ...** (or `S`) opens a save dialog in the chosen format; a quick-save also writes into `GenerativeLineArt/exports/`.
- **Save preset... / Load preset...** (or `P`, `L`) store/restore the whole setup as JSON in `GenerativeLineArt/presets/`.

## Plotting

Exported SVGs use millimetre units matching the chosen paper size, with each pen layer as a separate `<g>` (Inkscape layer) so multi-pen plots can be sent one layer at a time to software like Inkscape + the AxiDraw extension, vpype, or similar plotter tools.

**G-code** is written for GRBL-style pen plotters: millimetres, absolute coordinates, `G1` moves at the pen-down / travel speeds set on the Output tab, and the pen lifted either with the Z axis (`G0 Z<up>` / `G1 Z<down>`) or a servo (`M3 S<up>` / `M3 S<down>`). After every lift there is a `G4 P<seconds>` dwell (GRBL takes seconds; Marlin reads `P` as milliseconds, so set the lift time to 0 there). By default the origin is the bottom-left corner with Y pointing up; untick *Origin bottom-left* for a top-left origin. With several layers in one file the plotter returns to the origin and pauses (`M0`) for each pen change.

**HPGL** uses 40 plotter units per mm with the origin bottom-left; layer *n* is drawn with pen *n* (`SP1`–`SP4`), so a pen carousel can plot all layers in one go.

The time estimate is pen-down distance ÷ pen-down speed + travel ÷ travel speed + 2 × pen-lift time per stroke. Acceleration is ignored, so treat it as a rough guide.

## License

CC0 1.0 Universal — see [LICENSE](LICENSE).
