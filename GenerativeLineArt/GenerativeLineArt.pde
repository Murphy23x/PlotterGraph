// Generative Line Art  -  pen plotter edition
// ------------------------------------------------------------------
// Processing 4 (Java mode). No extra libraries needed.
//
// * 30 patterns (incl. image-driven), up to 4 independent pen layers (each:
//   pattern, seed, pen colour, pen width, scale / rotate / offset, mask)
// * live preview while you drag the sliders, undo / redo
// * export as SVG (millimetres, one Inkscape layer per pen), G-code or HPGL,
//   with path clean-up (simplify, merge, dedupe), pen-travel optimisation,
//   plot-time estimate, registration marks, pen test swatches, batch export
// * text / image masks: keep a layer only inside or outside a shape
// * presets: save / load the complete setup as a .json file
//
// Keys:  S  quick-export into the "exports" folder next to this sketch
//        P  quick-save preset into "presets"      L  load preset...
//        N / Space  new seed      R  randomize the current pattern
//        1-4  select layer        Left / Right  previous / next pattern
//        Ctrl+Z  undo             Ctrl+Y / Ctrl+Shift+Z  redo
// Mouse wheel over a slider = fine adjustment, elsewhere in the panel = scroll.
// Right-click a pattern parameter or the seed to lock it (Randomize,
// New seed and batch export leave locked values alone).

import java.util.*;
import java.io.File;

// ---------- constants -----------------------------------------------------
final int PANEL_W = 390;
final float PAD = 16;
final float GAP = 5;

final String[] PATTERN_NAMES = {
  "Flow field", "Wave lines", "Spirograph", "Noise rings", "Lissajous",
  "Contour map", "Truchet tiles", "Hatch shading", "Strange attractor", "Superformula",
  "Nested polygons", "Spiral", "Moire circles", "Circle packing", "Harmonograph",
  "Hilbert curve", "Sunburst", "Maze", "L-system", "Guilloche", "Maurer rose",
  "Phyllotaxis", "Subdivision", "Warped grid", "Fractal tree", "Voronoi",
  "Image", "Hex Truchet", "Penrose", "Hex maze"
};
final String[] FORMAT_NAMES = { "SVG", "G-code", "HPGL" };
final String[] FORMAT_EXT   = { "svg", "gcode", "hpgl" };
final String[] IMAGE_STYLES = { "TSP line", "Stipple", "Hatch", "Spiral", "Squiggle" };
final String[] PAPER_NAMES = { "A5", "A4", "A3", "Square" };
final float[][] PAPER_MM   = { {148, 210}, {210, 297}, {297, 420}, {250, 250} };
final String[] PEN_NAMES   = { "Black", "Red", "Blue", "Green", "Orange", "Purple", "Teal", "Brown" };
final int[] PEN_COLORS     = { 0xFF111111, 0xFFD62828, 0xFF1D4ED8, 0xFF15803D, 0xFFEA7A00, 0xFF7E22CE, 0xFF0E9AA7, 0xFF7C4A21 };
final int NUM_LAYERS = 4;
final String[] LSYS_NAMES  = { "Snowflake", "Dragon", "Gosper", "Sierpinski", "Plant" };

final int C_PANEL  = 0xFF1E1F22;
final int C_CANVAS = 0xFF2B2D31;
final int C_FIELD  = 0xFF2E3035;
final int C_TRACK  = 0xFF44474D;
final int C_TEXT   = 0xFFD8DADF;
final int C_DIM    = 0xFF8A8E96;
final int C_ACCENT = 0xFF3EC9B0;
final int C_HI     = 0xFFA5F3E4;

// ---------- state ---------------------------------------------------------
Random ui = new Random();          // UI randomness (pattern generation uses randomSeed)

Param pPaper, pLandscape, pMargin, pOptimize, pSeparate;
Param pSpeedDown, pSpeedUp, pLiftTime;                 // plotter (time estimate, G-code, HPGL)
Param pSimplify, pMerge, pMinLen, pDedupe;             // path clean-up
Param pMarks, pPenTest;                                // extras
Param pMaskSrc, pMaskSize, pMaskThr, pMaskInv;         // mask
Param pFormat, pLift, pFlipY, pZUp, pZDown, pServoUp, pServoDown, pBatch;   // export
ArrayList<Param> globals = new ArrayList<Param>();     // all page-level params (saved in presets)
ArrayList<Param> allParams = new ArrayList<Param>();   // fixed order snapshot used by undo / redo
Layer[] layers = new Layer[NUM_LAYERS];
int curLayer = 0;
Layer gen;                         // layer that is currently being generated

ArrayList<Widget> panelFlat = new ArrayList<Widget>();
Widget activeW = null;
Param activeParam = null;
boolean ddOpen = false;            // pattern dropdown open?
int panelTab = 0;                  // 0 = Design, 1 = Output
float panelScroll = 0, maxScroll = 0;
float clipTop = 0, clipBottom = 0; // visible band of the scrolling part of the panel
boolean textFocus = false;         // mask text field has keyboard focus
int lastChangeMs = -100000;        // last time any parameter changed (undo grouping)

ArrayList<float[]> undoStack = new ArrayList<float[]>(), redoStack = new ArrayList<float[]>();
float[] committed;

// mask (text or image), rasterised at MASK_K pixels per mm
final float MASK_K = 4;
String maskText = "PLOT";
PImage maskImg; PShape maskSvg; String maskPath = "";
int maskVersion = 0;
boolean[] maskBits; int maskW, maskH; String maskKey = "";
PFont maskFont;

// source photo for the Image pattern
PImage photo; String photoPath = "";
float[] photoLum; int photoW, photoH, photoVersion = 0;
float imgX, imgY, imgW, imgH;      // where the photo lands on the page (mm)

boolean previewStale = true;       // geometry changed -> redraw preview image
float genW = 210, genH = 297;      // page size in mm
float xmin, xmax, ymin, ymax;      // drawing area inside the margin
PGraphics pg;

File pendingExport, pendingPresetSave, pendingPresetLoad, pendingPhoto, pendingMask;
boolean pendingBatch = false;
String status = "";
int statusMs = -100000;

// ---------- setup / draw --------------------------------------------------
void setup() {
  size(1400, 900);
  surface.setTitle("Generative Line Art");
  surface.setResizable(true);
  textFont(createFont("SansSerif", 13));
  pPaper     = new Param(null, "Paper", PAPER_NAMES, 1);
  pLandscape = new Param(null, "Landscape", false);
  pMargin    = new Param(null, "Margin (mm)", 0, 60, 15, false);
  pOptimize  = new Param(null, "Optimize travel", true);
  pSeparate  = new Param(null, "File per layer", false);
  pSeparate.geometry = false;

  pSpeedDown = new Param(null, "Pen-down speed (mm/s)", 1, 150, 25, false);
  pSpeedUp   = new Param(null, "Travel speed (mm/s)", 5, 300, 80, false);
  pLiftTime  = new Param(null, "Pen lift (s)", 0, 1, 0.15, false);
  pSpeedDown.geometry = false; pSpeedUp.geometry = false; pLiftTime.geometry = false;

  pSimplify  = new Param(null, "Simplify (mm)", 0, 0.5, 0.05, false);
  pMerge     = new Param(null, "Merge gap (mm)", 0, 1, 0.1, false);
  pMinLen    = new Param(null, "Min length (mm)", 0, 3, 0.2, false);
  pDedupe    = new Param(null, "Remove duplicates", true);

  pMarks     = new Param(null, "Registration marks", false);
  pPenTest   = new Param(null, "Pen test swatch", false);

  pMaskSrc   = new Param(null, "Mask source", new String[] { "Text", "Image" }, 0);
  pMaskSize  = new Param(null, "Text size (mm)", 10, 250, 90, false);
  pMaskThr   = new Param(null, "Threshold", 0.05, 0.95, 0.5, false);
  pMaskInv   = new Param(null, "Invert", false);
  pMaskSrc.maskOnly = true; pMaskSize.maskOnly = true; pMaskThr.maskOnly = true; pMaskInv.maskOnly = true;

  pFormat    = new Param(null, "Export format", FORMAT_NAMES, 0);
  pLift      = new Param(null, "Pen lift", new String[] { "Z axis", "Servo M3" }, 0);
  pFlipY     = new Param(null, "Origin bottom-left", true);
  pZUp       = new Param(null, "Z up (mm)", 0, 20, 5, false);
  pZDown     = new Param(null, "Z down (mm)", -5, 5, 0, false);
  pServoUp   = new Param(null, "Servo up (S)", 0, 1000, 50, true);
  pServoDown = new Param(null, "Servo down (S)", 0, 1000, 30, true);
  pBatch     = new Param(null, "Batch count", 2, 50, 10, true);
  for (Param p : new Param[] { pFormat, pLift, pFlipY, pZUp, pZDown, pServoUp, pServoDown, pBatch }) p.geometry = false;
  pLift.wide = false;

  Collections.addAll(globals, pPaper, pLandscape, pMargin, pOptimize, pSeparate, pSpeedDown, pSpeedUp, pLiftTime,
    pSimplify, pMerge, pMinLen, pDedupe, pMarks, pPenTest, pMaskSrc, pMaskSize, pMaskThr, pMaskInv,
    pFormat, pLift, pFlipY, pZUp, pZDown, pServoUp, pServoDown, pBatch);

  layers[0] = new Layer(0, 0, 0, true, 1234);
  layers[1] = new Layer(1, 3, 1, false, 42);
  layers[2] = new Layer(2, 2, 2, false, 7);
  layers[3] = new Layer(3, 4, 3, false, 99);

  allParams.addAll(globals);
  for (Layer L : layers) {
    Collections.addAll(allParams, L.pEnabled, L.pColor, L.pPen, L.pMode, L.pSeed, L.pScale, L.pRot, L.pOffX, L.pOffY, L.pMask);
    for (ArrayList<Param> ps : L.modeParams) allParams.addAll(ps);
  }
  maskFont = createFont("SansSerif.bold", 96);
}

void draw() {
  background(C_CANVAS);
  if (pendingExport != null)     { File f = pendingExport;     pendingExport = null;     writeExport(f); }
  if (pendingPresetSave != null) { File f = pendingPresetSave; pendingPresetSave = null; savePreset(f); }
  if (pendingPresetLoad != null) { File f = pendingPresetLoad; pendingPresetLoad = null; loadPreset(f); }
  if (pendingPhoto != null)      { File f = pendingPhoto;      pendingPhoto = null;      loadPhoto(f); }
  if (pendingMask != null)       { File f = pendingMask;       pendingMask = null;       loadMaskImage(f); }

  updatePage();
  if (pendingBatch) { pendingBatch = false; batchExport(); }
  regenerate();
  buildPanel();
  drawPaper();
  drawPanel();
  drawStatusBar();
  trackUndo();
}

void regenerate() {
  for (Layer L : layers) {
    if (L.dirty && L.pEnabled.on()) { L.dirty = false; generateLayer(L); previewStale = true; }
  }
}

void updatePage() {
  float[] sz = PAPER_MM[pPaper.i()];
  float a = min(sz[0], sz[1]), b = max(sz[0], sz[1]);
  genW = pLandscape.on() ? b : a;
  genH = pLandscape.on() ? a : b;
  float m = min(pMargin.val, min(genW, genH) / 2 - 1);
  xmin = m; ymin = m; xmax = genW - m; ymax = genH - m;
}

// ---------- parameters / layers -------------------------------------------
class Param {
  Layer owner;         // null = global (page) parameter
  String label;
  float min, max, val, def;
  boolean isInt;
  boolean geometry = true;   // false: only changes how it looks/exports, not the paths
  boolean wide = false;      // takes a whole row in the panel
  boolean maskOnly = false;  // global mask setting: only layers that use the mask regenerate
  boolean locked = false;    // left alone by Randomize, New seed and batch export
  int type;                  // 0 slider, 1 toggle, 2 choice
  String[] opts;

  Param(Layer owner, String label, float min, float max, float def, boolean isInt) {
    this.owner = owner; this.label = label; this.min = min; this.max = max;
    this.val = def; this.def = def; this.isInt = isInt; this.type = 0;
  }
  Param(Layer owner, String label, boolean def) {
    this.owner = owner; this.label = label; this.min = 0; this.max = 1;
    this.val = def ? 1 : 0; this.def = this.val; this.isInt = true; this.type = 1;
  }
  Param(Layer owner, String label, String[] opts, int def) {
    this.owner = owner; this.label = label; this.opts = opts; this.min = 0; this.max = opts.length - 1;
    this.val = def; this.def = def; this.isInt = true; this.type = 2; this.wide = true;
  }
  void set(float v) {
    v = constrain(v, min, max);
    if (isInt) v = round(v);
    if (v == val) return;
    val = v;
    lastChangeMs = millis();
    if (!geometry) previewStale = true;
    else if (owner == null) { for (Layer L : layers) if (!maskOnly || L.pMask.i() > 0) L.dirty = true; }
    else owner.dirty = true;
  }
  int i() { return round(val); }
  boolean on() { return val > 0.5; }
}

class Layer {
  int id;
  Param pEnabled, pColor, pPen, pMode, pSeed, pScale, pRot, pOffX, pOffY, pMask;
  ArrayList<ArrayList<Param>> modeParams = new ArrayList<ArrayList<Param>>();
  ArrayList<ArrayList<PVector>> paths = new ArrayList<ArrayList<PVector>>();   // final plot order
  boolean dirty = true;
  int nPaths, nPoints;
  float length, travel;              // pen-down and pen-up distance (mm)

  Layer(int id, int mode, int colorIdx, boolean enabled, int seed) {
    this.id = id;
    pEnabled = new Param(this, "Enabled", enabled);
    pColor   = new Param(this, "Pen colour", PEN_NAMES, colorIdx);
    pPen     = new Param(this, "Pen width (mm)", 0.1, 2, 0.4, false);
    pMode    = new Param(this, "Pattern", PATTERN_NAMES, mode);
    pSeed    = new Param(this, "Seed", 0, 9999, seed, true);
    pScale   = new Param(this, "Scale", 0.1, 2, 1, false);
    pRot     = new Param(this, "Rotate (deg)", -180, 180, 0, false);
    pOffX    = new Param(this, "Offset X (mm)", -150, 150, 0, false);
    pOffY    = new Param(this, "Offset Y (mm)", -150, 150, 0, false);
    pMask    = new Param(this, "Mask", new String[] { "Off", "Inside", "Outside" }, 0);
    pEnabled.geometry = false; pColor.geometry = false; pPen.geometry = false;
    for (int m = 0; m < PATTERN_NAMES.length; m++) modeParams.add(makeParams(this, m));
  }
  ArrayList<Param> params() { return modeParams.get(pMode.i()); }
  int penColor() { return PEN_COLORS[pColor.i()]; }
  float seconds() {                  // estimated plot time
    return length / pSpeedDown.val + travel / pSpeedUp.val + nPaths * 2 * pLiftTime.val;
  }
}

Param P(Layer L, String label, float min, float max, float def, boolean isInt) {
  return new Param(L, label, min, max, def, isInt);
}

ArrayList<Param> makeParams(Layer L, int mode) {
  ArrayList<Param> l = new ArrayList<Param>();
  switch (mode) {
    case 0: // Flow field
      l.add(P(L, "Attempts",        50, 3000, 800, true));
      l.add(P(L, "Noise scale",    0.2,    8,   2, false));
      l.add(P(L, "Max steps",       10,  500, 150, true));
      l.add(P(L, "Step (mm)",      0.2,    4, 0.8, false));
      l.add(P(L, "Turbulence",     0.1,    3, 0.5, false));
      l.add(P(L, "Octaves",          1,    6,   2, true));
      l.add(P(L, "Base angle",       0,  360,   0, false));
      l.add(P(L, "Spacing (0=off)",  0,    6, 1.2, false));
      break;
    case 1: // Wave lines
      l.add(P(L, "Lines",             5, 150,  55, true));
      l.add(P(L, "Resolution",       50, 800, 300, true));
      l.add(P(L, "Amplitude",         0,  80,  22, false));
      l.add(P(L, "Noise scale",     0.3,  15,   4, false));
      l.add(P(L, "Drift",             0, 1.5, 0.25, false));
      l.add(P(L, "Center focus",      0,   1, 0.75, false));
      l.add(new Param(L, "Hide overlap", true));
      break;
    case 2: // Spirograph
      l.add(P(L, "Ring teeth",       30, 150, 105, true));
      l.add(P(L, "Wheel teeth",       5, 140,  44, true));
      l.add(P(L, "Pen offset",      0.1, 1.5, 0.85, false));
      l.add(P(L, "Copies",            1,  12,   1, true));
      l.add(P(L, "Rotate/copy",       0,  60,   4, false));
      l.add(P(L, "Scale/copy",      0.5,   1, 0.92, false));
      break;
    case 3: // Noise rings
      l.add(P(L, "Rings",             5, 150,  60, true));
      l.add(P(L, "Resolution",       60, 1000, 400, true));
      l.add(P(L, "Distortion",        0,  50,  14, false));
      l.add(P(L, "Noise scale",     0.1,   4,   1, false));
      l.add(P(L, "Drift",             0, 1.5, 0.25, false));
      l.add(P(L, "Inner radius",      0, 0.9, 0.05, false));
      break;
    case 4: // Lissajous
      l.add(P(L, "Freq X",            1,  12,   3, true));
      l.add(P(L, "Freq Y",            1,  12,   4, true));
      l.add(P(L, "Phase",             0, 360,  90, false));
      l.add(P(L, "Phase/copy",        0,  20, 1.5, false));
      l.add(P(L, "Copies",            1, 200,  40, true));
      l.add(P(L, "Resolution",      100, 3000, 800, true));
      l.add(P(L, "Shrink",            0, 0.9,   0, false));
      break;
    case 5: // Contour map
      l.add(P(L, "Levels",            3,  80,  28, true));
      l.add(P(L, "Resolution",       40, 300, 160, true));
      l.add(P(L, "Noise scale",     0.3,  10, 1.6, false));
      l.add(P(L, "Octaves",           1,   6,   3, true));
      l.add(P(L, "Warp",              0,   1, 0.3, false));
      l.add(P(L, "Island",            0,   1,   0, false));
      l.add(new Param(L, "Ridged", false));
      break;
    case 6: // Truchet tiles
      l.add(P(L, "Tiles",             3,  60,  14, true));
      l.add(new Param(L, "Style", new String[] { "Arcs", "Diagonals", "Fans" }, 0));
      l.add(P(L, "Lines/tile",        1,   8,   2, true));
      l.add(P(L, "Bias",              0,   1, 0.5, false));
      l.add(P(L, "Inset",             0, 0.8, 0.1, false));
      break;
    case 7: // Hatch shading
      l.add(P(L, "Spacing (mm)",    0.6,   8, 1.6, false));
      l.add(P(L, "Angle",             0, 180,  45, false));
      l.add(P(L, "Passes",            1,   4,   3, true));
      l.add(P(L, "Angle step",        0, 180,  60, false));
      l.add(P(L, "Noise scale",     0.3,  10, 2.5, false));
      l.add(P(L, "Coverage",        0.3, 0.9, 0.7, false));
      l.add(P(L, "Vignette",          0,   1,   0, false));
      break;
    case 8: // Strange attractor
      l.add(new Param(L, "Type", new String[] { "Clifford", "De Jong" }, 0));
      l.add(P(L, "a",               -3,   3, -1.4, false));
      l.add(P(L, "b",               -3,   3,  1.6, false));
      l.add(P(L, "c",               -3,   3,  1.0, false));
      l.add(P(L, "d",               -3,   3,  0.7, false));
      l.add(P(L, "Iterations",      200, 100000, 2500, true));
      l.add(P(L, "Strands",           1,  40,   1, true));
      break;
    case 9: // Superformula
      l.add(P(L, "Shapes",            1, 120,  40, true));
      l.add(P(L, "Lobes m",           1,  24,   6, true));
      l.add(P(L, "n1",              0.1,  10, 0.7, false));
      l.add(P(L, "n2",              0.1,  10, 1.6, false));
      l.add(P(L, "n3",              0.1,  10, 1.6, false));
      l.add(P(L, "Inner size",        0, 0.95, 0.05, false));
      l.add(P(L, "Twist",          -180, 180,  30, false));
      l.add(P(L, "Resolution",      200, 2000, 600, true));
      break;
    case 10: // Nested polygons
      l.add(P(L, "Sides",             3,  12,   4, true));
      l.add(P(L, "Layers",            2, 200,  45, true));
      l.add(P(L, "Twist/step",        0,  20, 4.0, false));
      l.add(P(L, "Shrink/step",     0.8, 0.995, 0.93, false));
      l.add(P(L, "Drift X",          -4,   4,   0, false));
      l.add(P(L, "Drift Y",          -4,   4,   0, false));
      break;
    case 11: // Spiral
      l.add(P(L, "Turns",             1, 150,  45, true));
      l.add(P(L, "Arms",              1,  12,   1, true));
      l.add(P(L, "Points/turn",      30, 400, 120, true));
      l.add(P(L, "Wobble (mm)",       0,  20,   3, false));
      l.add(P(L, "Wobble scale",    0.2,   8, 1.5, false));
      l.add(P(L, "Page fit",          0,   1, 0.6, false));
      l.add(P(L, "Hole",              0, 0.9, 0.02, false));
      break;
    case 12: // Moire circles
      l.add(P(L, "Circle sets",       2,   5,   2, true));
      l.add(P(L, "Rings",            10, 250,  55, true));
      l.add(P(L, "Spacing (mm)",    0.5,   5, 2.4, false));
      l.add(P(L, "Spread (mm)",       0, 150,  18, false));
      l.add(P(L, "Rotation",          0, 360,   0, false));
      l.add(P(L, "Resolution",      100, 800, 360, true));
      break;
    case 13: // Circle packing
      l.add(P(L, "Attempts",        500, 20000, 6000, true));
      l.add(P(L, "Min radius",      0.8,  10,   2, false));
      l.add(P(L, "Max radius",        5, 100,  40, false));
      l.add(P(L, "Padding",           0,   5, 0.8, false));
      l.add(P(L, "Ring gap (0=off)",  0,   5, 1.2, false));
      break;
    case 14: // Harmonograph
      l.add(P(L, "Freq X",            1,   8,   2, true));
      l.add(P(L, "Freq Y",            1,   8,   3, true));
      l.add(P(L, "Detune X",      -0.05, 0.05, 0.003, false));
      l.add(P(L, "Detune Y",      -0.05, 0.05, -0.002, false));
      l.add(P(L, "Phase",             0, 360,  90, false));
      l.add(P(L, "Damping",       0.0005, 0.03, 0.004, false));
      l.add(P(L, "Duration",         10, 400, 100, false));
      l.add(P(L, "Steps",          2000, 60000, 15000, true));
      break;
    case 15: // Hilbert curve
      l.add(P(L, "Order",             1,   8,   5, true));
      l.add(P(L, "Smooth",            0,   3,   0, true));
      l.add(P(L, "Jitter",            0,   1,   0, false));
      l.add(new Param(L, "Stretch to page", false));
      break;
    case 16: // Sunburst
      l.add(P(L, "Rays",             30, 1500, 300, true));
      l.add(P(L, "Inner radius",      0, 0.9, 0.15, false));
      l.add(P(L, "Length var",        0,   1, 0.6, false));
      l.add(P(L, "Noise scale",     0.2,   8,   2, false));
      l.add(P(L, "Twist",          -180, 180,  40, false));
      l.add(P(L, "Inner var",         0,   1,   0, false));
      break;
    case 17: // Maze
      l.add(P(L, "Cells",             4, 100,  24, true));
      l.add(new Param(L, "Style", new String[] { "Walls", "Path" }, 0));
      l.add(P(L, "Straightness",      0,   1, 0.3, false));
      l.add(P(L, "Loops",             0,   1,   0, false));
      l.add(new Param(L, "Entrance/exit", true));
      break;
    case 18: // L-system
      l.add(new Param(L, "Type", LSYS_NAMES, 0));
      l.add(P(L, "Iterations",        1,  16,   4, true));
      l.add(P(L, "Angle tweak",     -15,  15,   0, false));
      l.add(P(L, "Jitter",            0, 0.5,   0, false));
      l.add(P(L, "Smooth",            0,   3,   0, true));
      break;
    case 19: // Guilloche
      l.add(P(L, "Lines",             1,  60,  10, true));
      l.add(P(L, "Oscillations",      3, 100,  28, true));
      l.add(P(L, "Outer radius",    0.2,   1, 0.95, false));
      l.add(P(L, "Inner radius",      0, 0.95, 0.35, false));
      l.add(P(L, "Outer lobes",       0,  24,  12, true));
      l.add(P(L, "Inner lobes",       0,  24,   6, true));
      l.add(P(L, "Lobe depth",        0, 0.5, 0.12, false));
      l.add(P(L, "Resolution",      300, 6000, 2000, true));
      break;
    case 20: // Maurer rose
      l.add(P(L, "Petals n",          1,  12,   6, true));
      l.add(P(L, "Step d (deg)",      1, 359,  71, true));
      l.add(P(L, "Points",           60, 3600, 361, true));
      l.add(P(L, "Copies",            1,   8,   1, true));
      l.add(P(L, "d / copy",          1,  30,   1, true));
      l.add(new Param(L, "Draw rose", true));
      break;
    case 21: // Phyllotaxis
      l.add(P(L, "Points",           50, 4000, 900, true));
      l.add(P(L, "Angle tweak",      -3,   3,   0, false));
      l.add(new Param(L, "Mark", new String[] { "Circles", "Dashes", "Spirals" }, 0));
      l.add(P(L, "Dot size (mm)",   0.3,   8, 2.4, false));
      l.add(P(L, "Size growth",       0,   1, 0.7, false));
      l.add(P(L, "Rings / dashes",    1,   5,   1, true));
      l.add(P(L, "Spiral family",     3,   9,   6, true));
      break;
    case 22: // Subdivision
      l.add(P(L, "Depth",             1,  14,   8, true));
      l.add(P(L, "Min size (mm)",     2,  60,   8, false));
      l.add(P(L, "Split variance",    0, 0.45, 0.3, false));
      l.add(P(L, "Stop chance",       0, 0.7, 0.2, false));
      l.add(P(L, "Fill amount",       0,   1, 0.5, false));
      l.add(P(L, "Hatch (mm)",      0.4,   6, 1.2, false));
      l.add(P(L, "Gap (mm)",          0,   6, 1.5, false));
      break;
    case 23: // Warped grid
      l.add(P(L, "Lines",             5, 250,  70, true));
      l.add(new Param(L, "Direction", new String[] { "Horizontal", "Vertical", "Grid" }, 0));
      l.add(P(L, "Bulges",            1,   8,   1, true));
      l.add(P(L, "Strength",         -1, 1.5, 0.9, false));
      l.add(P(L, "Radius",         0.05,   1, 0.35, false));
      l.add(P(L, "Noise warp (mm)",   0,  20,   0, false));
      l.add(P(L, "Resolution",       50, 1000, 400, true));
      break;
    case 24: // Fractal tree
      l.add(P(L, "Depth",             2,  14,  10, true));
      l.add(P(L, "Branches",          2,   4,   2, true));
      l.add(P(L, "Branch angle",      5,  90,  25, false));
      l.add(P(L, "Angle var",         0,   1, 0.35, false));
      l.add(P(L, "Length ratio",    0.5, 0.9, 0.72, false));
      l.add(P(L, "Length var",        0, 0.5, 0.2, false));
      l.add(P(L, "Bend",            -40,  40,   0, false));
      break;
    case 25: // Voronoi
      l.add(P(L, "Cells",             5, 800, 150, true));
      l.add(P(L, "Relax",             0,  10,   2, true));
      l.add(P(L, "Center bias",       0,   1,   0, false));
      l.add(P(L, "Inset rings",       0,  12,   3, true));
      l.add(P(L, "Ring gap (mm)",   0.4,   6, 1.2, false));
      l.add(P(L, "Smooth",            0,   4,   2, true));
      l.add(new Param(L, "Borders", true));
      break;
    case 26: // Image
      l.add(new Param(L, "Style", IMAGE_STYLES, 0));
      l.add(P(L, "Points",          200, 12000, 5000, true));
      l.add(P(L, "Lines / turns",    10, 250,  70, true));
      l.add(P(L, "Contrast",        0.2,   3, 1.2, false));
      l.add(P(L, "Brightness",     -0.5, 0.5,   0, false));
      l.add(P(L, "Angle",             0, 180,  45, false));
      l.add(P(L, "Amplitude",       0.1, 1.5, 0.9, false));
      l.add(P(L, "Frequency",       0.1,   3, 0.8, false));
      l.add(P(L, "Dot size (mm)",   0.2,   3, 0.6, false));
      l.add(new Param(L, "Invert", false));
      break;
    case 27: // Hex Truchet
      l.add(P(L, "Tiles",             3,  40,  12, true));
      l.add(new Param(L, "Style", new String[] { "Arcs", "Mixed", "Random" }, 0));
      l.add(P(L, "Lines/tile",        1,   5,   1, true));
      l.add(P(L, "Bias",              0,   1, 0.5, false));
      l.add(P(L, "Spread",            0, 0.9, 0.6, false));
      l.add(new Param(L, "Hex outline", false));
      break;
    case 28: // Penrose
      l.add(P(L, "Divisions",         1,   8,   5, true));
      l.add(new Param(L, "Style", new String[] { "Rhombs", "Arcs", "Both" }, 0));
      l.add(P(L, "Zoom",            0.3,   4,   1, false));
      l.add(P(L, "Rotation",          0,  72,   0, false));
      break;
    case 29: // Hex maze
      l.add(P(L, "Cells",             4,  60,  18, true));
      l.add(new Param(L, "Style", new String[] { "Walls", "Path" }, 0));
      l.add(P(L, "Loops",             0,   1,   0, false));
      l.add(new Param(L, "Entrance/exit", true));
      break;
  }
  return l;
}

float pv(int i) { return gen.params().get(i).val; }

void randomizeLayer(Layer L) {
  if (!L.pSeed.locked) L.pSeed.set(ui.nextInt(10000));
  for (Param p : L.params()) {
    if (p.type == 1 || p.locked) continue;
    float lo = p.min + 0.08 * (p.max - p.min);
    float hi = p.min + 0.75 * (p.max - p.min);
    p.set(lo + ui.nextFloat() * (hi - lo));
  }
}

void newSeed(Layer L) {
  if (L.pSeed.locked) setStatus("Seed is locked (right-click it to unlock)");
  else L.pSeed.set(ui.nextInt(10000));
}

void resetLayer(Layer L) {
  for (Param p : L.params()) p.set(p.def);
}

// Parameters that can be locked: the current pattern's parameters and the seed.
boolean lockable(Param p) {
  if (p == null || p.owner == null) return false;
  return p == p.owner.pSeed || p.owner.params().contains(p);
}

// ---------- undo / redo ---------------------------------------------------
// The state is the value of every parameter. Changes are committed once the
// mouse is released and nothing has changed for a moment, so one slider drag
// or a burst of mouse-wheel ticks becomes a single undo step.
float[] captureState() {
  float[] s = new float[allParams.size()];
  for (int i = 0; i < s.length; i++) s[i] = allParams.get(i).val;
  return s;
}

void applyState(float[] s) {
  for (int i = 0; i < s.length; i++) allParams.get(i).set(s[i]);
}

void commitPending() {
  float[] s = captureState();
  if (committed == null) { committed = s; return; }
  if (Arrays.equals(s, committed)) return;
  undoStack.add(committed);
  if (undoStack.size() > 200) undoStack.remove(0);
  redoStack.clear();
  committed = s;
}

void trackUndo() {
  if (activeW != null || millis() - lastChangeMs < 300) return;
  commitPending();
}

void undo() {
  if (activeW != null) return;
  commitPending();
  if (undoStack.isEmpty()) { setStatus("Nothing to undo"); return; }
  redoStack.add(committed);
  committed = undoStack.remove(undoStack.size() - 1);
  applyState(committed);
  setStatus("Undo (" + undoStack.size() + " more)");
}

void redo() {
  if (activeW != null) return;
  commitPending();
  if (redoStack.isEmpty()) { setStatus("Nothing to redo"); return; }
  undoStack.add(committed);
  committed = redoStack.remove(redoStack.size() - 1);
  applyState(committed);
  setStatus("Redo (" + redoStack.size() + " more)");
}

// ---------- actions -------------------------------------------------------
void action(int id) {
  Layer L = layers[curLayer];
  switch (id) {
    case 0: newSeed(L); break;
    case 1: randomizeLayer(L); break;
    case 2: resetLayer(L); break;
    case 3: requestExport(); break;
    case 4: requestPresetSave(); break;
    case 5: requestPresetLoad(); break;
    case 6: undo(); break;
    case 7: redo(); break;
    case 8: pendingBatch = true; setStatus("Batch export running..."); break;
    case 9: selectInput("Choose a photo / image", "photoSelected"); break;
    case 10: selectInput("Choose a mask image (PNG, JPG, GIF or SVG)", "maskSelected"); break;
    case 11: maskImg = null; maskSvg = null; maskPath = ""; maskChanged(); break;
    case 12: photo = null; photoLum = null; photoPath = ""; photoChanged(); break;
  }
}

void keyPressed() {
  if (textFocus) { typeMaskText(); return; }
  Layer L = layers[curLayer];
  boolean ctrl = keyEvent != null && (keyEvent.isControlDown() || keyEvent.isMetaDown());
  if (ctrl) {
    boolean shift = keyEvent.isShiftDown();
    if (keyCode == 'Z') { if (shift) redo(); else undo(); }
    else if (keyCode == 'Y') redo();
    return;
  }
  if (key == CODED) {
    if (keyCode == RIGHT) L.pMode.set((L.pMode.i() + 1) % PATTERN_NAMES.length);
    else if (keyCode == LEFT) L.pMode.set((L.pMode.i() + PATTERN_NAMES.length - 1) % PATTERN_NAMES.length);
    return;
  }
  if (key == 's' || key == 'S') quickSave();
  else if (key == 'p' || key == 'P') quickSavePreset();
  else if (key == 'l' || key == 'L') requestPresetLoad();
  else if (key == 'n' || key == 'N' || key == ' ') newSeed(L);
  else if (key == 'r' || key == 'R') randomizeLayer(L);
  else if (key >= '1' && key <= '0' + NUM_LAYERS) curLayer = key - '1';
}

// Keyboard input while the mask text field has focus.
void typeMaskText() {
  if (key == ESC) { key = 0; textFocus = false; return; }    // don't let Esc quit the sketch
  if (key == CODED) return;
  if (key == ENTER || key == RETURN || key == TAB) { textFocus = false; return; }
  if (key == BACKSPACE) {
    if (maskText.length() > 0) { maskText = maskText.substring(0, maskText.length() - 1); maskChanged(); }
  } else if (key >= 32 && key != DELETE && maskText.length() < 60) {
    maskText += key;
    maskChanged();
  }
}

// ---------- GUI widgets ---------------------------------------------------
abstract class Widget {
  float x, y, w, h;
  Param p;                       // parameter this widget edits (if any)
  boolean scrolls = false;       // part of the scrolling middle of the panel
  abstract void display();
  void press() {}
  void drag() {}
  boolean hit() {
    if (scrolls && (mouseY < clipTop || mouseY > clipBottom)) return false;
    return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  }
}

// Small padlock drawn next to the label of a locked parameter.
void drawLock(float x, float y) {
  noFill(); stroke(C_HI); strokeWeight(1.4);
  arc(x + 4, y + 5, 6, 7, PI, TWO_PI);
  noStroke(); fill(C_HI); rect(x, y + 5, 8, 6, 1);
}

class InfoW extends Widget {
  String t;
  InfoW(String t) { this.t = t; h = 15 * (split(t, '\n').length) + 4; }
  void display() {
    fill(C_DIM); textSize(11); textAlign(LEFT, TOP);
    textLeading(15);
    text(t, x, y + 2);
  }
}

class TextFieldW extends Widget {
  String label;
  TextFieldW(String label) { this.label = label; h = 40; }
  void display() {
    textSize(11); fill(C_DIM); textAlign(LEFT, TOP); text(label.toUpperCase(), x, y);
    stroke(textFocus ? C_ACCENT : C_TRACK); strokeWeight(1); fill(C_FIELD);
    rect(x, y + 16, w, 24, 4);
    noStroke(); fill(C_TEXT); textSize(12); textAlign(LEFT, CENTER);
    String t = maskText;
    while (t.length() > 0 && textWidth(t) > w - 20) t = t.substring(1);
    text(t, x + 8, y + 27);
    if (textFocus && (millis() / 500) % 2 == 0) { stroke(C_ACCENT); line(x + 9 + textWidth(t), y + 20, x + 9 + textWidth(t), y + 35); }
  }
  void press() { textFocus = true; }
}

class TabsW extends Widget {
  String[] labels = { "Design", "Output" };
  TabsW() { h = 26; }
  void display() {
    float bw = w / labels.length;
    for (int i = 0; i < labels.length; i++) {
      boolean sel = (i == panelTab);
      noStroke(); fill(sel ? C_ACCENT : C_FIELD); rect(x + i * bw, y, bw - 3, h, 5);
      fill(sel ? C_PANEL : C_TEXT); textSize(12); textAlign(CENTER, CENTER);
      text(labels[i], x + i * bw + (bw - 3) / 2, y + h / 2 - 1);
    }
  }
  void press() {
    int t = constrain(floor((mouseX - x) / (w / labels.length)), 0, labels.length - 1);
    if (t != panelTab) { panelTab = t; panelScroll = 0; ddOpen = false; }
  }
}

class Header extends Widget {
  String t;
  Header(String t) { this.t = t; h = 24; }
  void display() {
    fill(C_DIM); textSize(11); textAlign(LEFT, BOTTOM);
    text(t, x, y + h - 5);
    stroke(C_TRACK); strokeWeight(1); line(x, y + h - 1, x + w, y + h - 1);
  }
}

class SliderW extends Widget {
  SliderW(Param p) { this.p = p; h = 32; }
  void display() {
    textSize(12);
    fill(C_TEXT); textAlign(LEFT, TOP); text(p.label, x, y);
    if (p.locked) drawLock(x + textWidth(p.label) + 6, y + 1);
    fill(C_ACCENT); textAlign(RIGHT, TOP); text(fmtParam(p), x + w, y);
    float ty = y + 25, x0 = x + 6, x1 = x + w - 6;
    strokeCap(ROUND); stroke(C_TRACK); strokeWeight(3); line(x0, ty, x1, ty);
    float k = map(p.val, p.min, p.max, x0, x1);
    stroke(C_ACCENT); line(x0, ty, k, ty);
    noStroke(); fill((activeParam == p || (activeParam == null && hit())) ? C_HI : C_ACCENT);
    ellipse(k, ty, 13, 13);
  }
  void press() { drag(); }
  void drag() {
    float x0 = x + 6, x1 = x + w - 6;
    p.set(map(constrain(mouseX, x0, x1), x0, x1, p.min, p.max));
  }
}

class ToggleW extends Widget {
  ToggleW(Param p) { this.p = p; h = 22; }
  void display() {
    stroke(C_TRACK); strokeWeight(1);
    fill(p.on() ? C_ACCENT : C_FIELD);
    rect(x, y + 3, 15, 15, 3);
    if (p.on()) { stroke(C_PANEL); strokeWeight(2); line(x + 3, y + 10, x + 6.5, y + 14); line(x + 6.5, y + 14, x + 12, y + 6); }
    noStroke(); fill(C_TEXT); textSize(12); textAlign(LEFT, CENTER);
    text(p.label, x + 24, y + 10);
    if (p.locked) drawLock(x + 30 + textWidth(p.label), y + 4);
  }
  void press() { p.set(p.on() ? 0 : 1); }
}

class ChoiceW extends Widget {
  int perRow, rows;
  Param extra;                   // optional toggle drawn at the right of the label line
  ChoiceW(Param p, int perRow, Param extra) {
    this.p = p; this.perRow = perRow; this.extra = extra;
    rows = ceil(p.opts.length / (float) perRow);
    h = 16 + rows * 26;
  }
  boolean overExtra() { return extra != null && mouseY < y + 16 && mouseX > x + w - 90; }
  void display() {
    textSize(11); fill(C_DIM); textAlign(LEFT, TOP); text(p.label.toUpperCase(), x, y);
    if (p.locked) drawLock(x + textWidth(p.label.toUpperCase()) + 6, y);
    if (extra != null) {
      float ex = x + w - 88;
      stroke(C_TRACK); strokeWeight(1); fill(extra.on() ? C_ACCENT : C_FIELD); rect(ex, y, 12, 12, 2);
      noStroke(); fill(C_TEXT); textAlign(LEFT, TOP); text(extra.label, ex + 18, y);
    }
    float sw = (w - (perRow - 1) * 3) / perRow;
    for (int i = 0; i < p.opts.length; i++) {
      float bx = x + (i % perRow) * (sw + 3), by = y + 16 + (i / perRow) * 26;
      boolean sel = (i == p.i());
      boolean over = mouseX >= bx && mouseX <= bx + sw && mouseY >= by && mouseY <= by + 23;
      noStroke(); fill(sel ? C_ACCENT : (over ? C_TRACK : C_FIELD));
      rect(bx, by, sw, 23, 4);
      fill(sel ? C_PANEL : C_TEXT); textSize(12); textAlign(CENTER, CENTER);
      text(p.opts[i], bx + sw / 2, by + 11);
    }
  }
  void press() {
    if (overExtra()) { extra.set(extra.on() ? 0 : 1); return; }
    float sw = (w - (perRow - 1) * 3) / perRow;
    for (int i = 0; i < p.opts.length; i++) {
      float bx = x + (i % perRow) * (sw + 3), by = y + 16 + (i / perRow) * 26;
      if (mouseX >= bx && mouseX <= bx + sw && mouseY >= by && mouseY <= by + 23) p.set(i);
    }
  }
}

class SwatchW extends Widget {
  SwatchW(Param p) { this.p = p; h = 22; }
  float sz() { return min(20, (w - 7 * 4) / 8.0); }
  void display() {
    float sz = sz();
    for (int i = 0; i < PEN_COLORS.length; i++) {
      float bx = x + i * (sz + 4);
      noStroke(); fill(PEN_COLORS[i]); rect(bx, y + 1, sz, sz, 4);
      if (i == p.i()) { noFill(); stroke(C_HI); strokeWeight(2); rect(bx - 2, y - 1, sz + 4, sz + 4, 5); }
    }
  }
  void press() {
    float sz = sz();
    for (int i = 0; i < PEN_COLORS.length; i++) {
      float bx = x + i * (sz + 4);
      if (mouseX >= bx - 2 && mouseX <= bx + sz + 2) p.set(i);
    }
  }
}

class LayerTabsW extends Widget {
  LayerTabsW() { h = 30; }
  float tw() { return (w - (NUM_LAYERS - 1) * 4) / NUM_LAYERS; }
  void display() {
    float tw = tw();
    for (int i = 0; i < NUM_LAYERS; i++) {
      Layer L = layers[i];
      float bx = x + i * (tw + 4);
      boolean sel = (i == curLayer);
      noStroke(); fill(sel ? C_TRACK : C_FIELD); rect(bx, y, tw, h, 5);
      if (sel) { noFill(); stroke(C_ACCENT); strokeWeight(2); rect(bx + 1, y + 1, tw - 2, h - 2, 5); }
      float alpha = L.pEnabled.on() ? 255 : 90;
      noStroke(); fill(red(L.penColor()), green(L.penColor()), blue(L.penColor()), alpha);
      ellipse(bx + 16, y + h / 2, 12, 12);
      fill(red(C_TEXT), green(C_TEXT), blue(C_TEXT), alpha); textSize(12); textAlign(LEFT, CENTER);
      text("Layer " + (i + 1), bx + 28, y + h / 2 - 1);
    }
  }
  void press() {
    float tw = tw();
    for (int i = 0; i < NUM_LAYERS; i++) {
      float bx = x + i * (tw + 4);
      if (mouseX >= bx && mouseX <= bx + tw) curLayer = i;
    }
  }
}

class DropdownW extends Widget {
  DropdownW(Param p) { this.p = p; h = 40; }
  float listX() { return x; }
  float listY() { return y + 42; }
  float itemH() { return 22; }
  float colW() { return w / 2; }
  void display() {
    textSize(11); fill(C_DIM); textAlign(LEFT, TOP); text("PATTERN", x, y);
    noStroke(); fill(ddOpen ? C_TRACK : C_FIELD); rect(x, y + 16, w, 24, 4);
    fill(C_TEXT); textSize(12); textAlign(LEFT, CENTER); text(p.opts[p.i()], x + 10, y + 27);
    fill(C_ACCENT); triangle(x + w - 20, y + 24, x + w - 10, y + 24, x + w - 15, y + 32);
  }
  void overlay() {
    if (!ddOpen) return;
    int n = p.opts.length, rowsN = ceil(n / 2.0);
    float lx = listX(), ly = listY(), ih = itemH(), cw = colW();
    noStroke(); fill(0, 120); rect(lx + 3, ly + 4, w, rowsN * ih + 8, 6);
    fill(C_FIELD); stroke(C_TRACK); strokeWeight(1); rect(lx, ly, w, rowsN * ih + 8, 6);
    for (int i = 0; i < n; i++) {
      float ix = lx + (i / rowsN) * cw, iy = ly + 4 + (i % rowsN) * ih;
      boolean over = mouseX >= ix && mouseX <= ix + cw && mouseY >= iy && mouseY <= iy + ih;
      boolean sel = (i == p.i());
      noStroke(); fill(sel ? C_ACCENT : (over ? C_TRACK : C_FIELD)); rect(ix + 3, iy, cw - 6, ih - 2, 4);
      fill(sel ? C_PANEL : C_TEXT); textSize(12); textAlign(LEFT, CENTER); text(p.opts[i], ix + 12, iy + ih / 2 - 1);
    }
  }
  void press() { ddOpen = true; }
  void clickItem() {
    int n = p.opts.length, rowsN = ceil(n / 2.0);
    float lx = listX(), ly = listY(), ih = itemH(), cw = colW();
    for (int i = 0; i < n; i++) {
      float ix = lx + (i / rowsN) * cw, iy = ly + 4 + (i % rowsN) * ih;
      if (mouseX >= ix && mouseX <= ix + cw && mouseY >= iy && mouseY <= iy + ih) p.set(i);
    }
  }
}

class ButtonRow extends Widget {
  String[] labels; int[] ids;
  ButtonRow(String[] labels, int[] ids) { this.labels = labels; this.ids = ids; h = 30; }
  float bw() { return (w - (labels.length - 1) * 4) / labels.length; }
  void display() {
    float bw = bw();
    for (int i = 0; i < labels.length; i++) {
      float bx = x + i * (bw + 4);
      boolean over = mouseX >= bx && mouseX <= bx + bw && mouseY >= y && mouseY <= y + h;
      boolean main = (ids[i] == 3);
      noStroke();
      fill(main ? (over ? C_HI : C_ACCENT) : (over ? C_TRACK : C_FIELD));
      rect(bx, y, bw, h, 5);
      fill(main ? C_PANEL : C_TEXT); textSize(12); textAlign(CENTER, CENTER);
      text(labels[i], bx + bw / 2, y + h / 2 - 1);
    }
  }
  void press() {
    float bw = bw();
    for (int i = 0; i < labels.length; i++) {
      float bx = x + i * (bw + 4);
      if (mouseX >= bx && mouseX <= bx + bw) action(ids[i]);
    }
  }
}

// Lays several widgets side by side. Only a layout helper: the children are
// what gets drawn and clicked.
class RowW extends Widget {
  Widget[] kids; float[] weights;
  RowW(Widget[] kids, float[] weights) {
    this.kids = kids; this.weights = weights;
    for (Widget k : kids) h = max(h, k.h);
  }
  void arrange() {
    float total = 0; for (float f : weights) total += f;
    float usable = w - 10 * (weights.length - 1);
    float cx = x;
    for (int i = 0; i < kids.length; i++) {
      float kw = usable * weights[i] / total;
      kids[i].x = cx; kids[i].y = y; kids[i].w = kw;
      cx += kw + 10;
    }
  }
  void display() {}
}

Widget row(Widget a, Widget b) { return new RowW(new Widget[] { a, b }, new float[] { 1, 1 }); }

float stack(ArrayList<Widget> ws, float y, boolean scrolls) {
  for (Widget w : ws) {
    w.x = PAD; w.w = PANEL_W - 2 * PAD; w.y = y;
    if (w instanceof RowW) {
      RowW r = (RowW) w;
      r.arrange();
      for (Widget k : r.kids) { k.scrolls = scrolls; panelFlat.add(k); }
    } else { w.scrolls = scrolls; panelFlat.add(w); }
    y += w.h + GAP;
  }
  return y;
}

void addParamWidgets(ArrayList<Widget> top, ArrayList<Param> ps) {
  Widget pending = null;
  for (Param p : ps) {
    Widget wd = p.type == 1 ? new ToggleW(p) : (p.type == 2 ? new ChoiceW(p, p.opts.length, null) : new SliderW(p));
    if (p.wide) {
      if (pending != null) { top.add(new RowW(new Widget[] { pending }, new float[] { 1, 1 })); pending = null; }
      top.add(wd);
    } else if (pending == null) pending = wd;
    else { top.add(row(pending, wd)); pending = null; }
  }
  if (pending != null) top.add(new RowW(new Widget[] { pending }, new float[] { 1, 1 }));
}

void buildDesignTab(ArrayList<Widget> top) {
  Layer L = layers[curLayer];
  top.add(new ChoiceW(pPaper, 4, pLandscape));
  top.add(new SliderW(pMargin));
  top.add(new Header("PEN LAYERS  (each layer = one pen)"));
  top.add(new LayerTabsW());
  top.add(new RowW(new Widget[] { new ToggleW(L.pEnabled), new SwatchW(L.pColor) }, new float[] { 1, 2 }));
  top.add(new DropdownW(L.pMode));
  top.add(row(new SliderW(L.pPen), new SliderW(L.pSeed)));
  top.add(new ButtonRow(new String[] { "New seed", "Randomize", "Reset", "Undo", "Redo" }, new int[] { 0, 1, 2, 6, 7 }));
  top.add(new Header("PATTERN PARAMETERS  (right-click = lock)"));
  if (L.pMode.i() == 26) {
    top.add(new ButtonRow(new String[] { "Load image...", "Use demo" }, new int[] { 9, 12 }));
    top.add(new InfoW(photo == null ? "No image loaded: showing a built-in demo" : "Image: " + new File(photoPath).getName()));
  }
  addParamWidgets(top, L.params());

  top.add(new Header("LAYER TRANSFORM"));
  top.add(row(new SliderW(L.pScale), new SliderW(L.pRot)));
  top.add(row(new SliderW(L.pOffX), new SliderW(L.pOffY)));
  top.add(new ChoiceW(L.pMask, 3, null));
}

void buildOutputTab(ArrayList<Widget> top) {
  top.add(new Header("PLOT TIME ESTIMATE"));
  top.add(row(new SliderW(pSpeedDown), new SliderW(pSpeedUp)));
  top.add(new RowW(new Widget[] { new SliderW(pLiftTime) }, new float[] { 1, 1 }));
  StringBuilder est = new StringBuilder();
  for (Layer L : layers) {
    if (!L.pEnabled.on()) continue;
    if (est.length() > 0) est.append('\n');
    est.append("Layer ").append(L.id + 1).append("  ").append(fmtTime(L.seconds())).append("   ")
      .append(String.format(Locale.US, "%.1f m down, %.1f m travel, %d lifts", L.length / 1000, L.travel / 1000, L.nPaths));
  }
  top.add(new InfoW(est.length() == 0 ? "No layers enabled" : est.toString()));

  top.add(new Header("PATH CLEAN-UP"));
  top.add(row(new SliderW(pSimplify), new SliderW(pMerge)));
  top.add(row(new SliderW(pMinLen), new ToggleW(pDedupe)));
  top.add(row(new ToggleW(pOptimize), new ToggleW(pSeparate)));

  top.add(new Header("EXTRAS  (drawn by every enabled pen)"));
  top.add(row(new ToggleW(pMarks), new ToggleW(pPenTest)));

  top.add(new Header("MASK  (switch it on per layer, Design tab)"));
  top.add(new ChoiceW(pMaskSrc, 2, pMaskInv));
  if (pMaskSrc.i() == 0) {
    top.add(row(new TextFieldW("Text  ( | = new line)"), new SliderW(pMaskSize)));
  } else {
    top.add(new ButtonRow(new String[] { "Load mask image...", "Clear" }, new int[] { 10, 11 }));
    top.add(row(new SliderW(pMaskThr), new InfoW(maskPath.isEmpty() ? "No image loaded" : new File(maskPath).getName())));
  }

  top.add(new Header("EXPORT"));
  top.add(new ChoiceW(pFormat, 3, null));
  if (pFormat.i() == 1) {
    top.add(row(new ChoiceW(pLift, 2, null), new ToggleW(pFlipY)));
    if (pLift.i() == 0) top.add(row(new SliderW(pZUp), new SliderW(pZDown)));
    else top.add(row(new SliderW(pServoUp), new SliderW(pServoDown)));
  }
  top.add(row(new SliderW(pBatch), new ButtonRow(new String[] { "Batch export" }, new int[] { 8 })));
}

void buildPanel() {
  ArrayList<Widget> top = new ArrayList<Widget>();
  if (panelTab == 0) buildDesignTab(top);
  else buildOutputTab(top);

  ArrayList<Widget> bottom = new ArrayList<Widget>();
  bottom.add(new ButtonRow(new String[] { "Save preset...", "Load preset..." }, new int[] { 4, 5 }));
  Widget exp = new ButtonRow(new String[] { "Export " + FORMAT_NAMES[pFormat.i()] + "..." }, new int[] { 3 });
  exp.h = 36;
  bottom.add(exp);

  panelFlat = new ArrayList<Widget>();
  TabsW tabs = new TabsW();
  tabs.x = PANEL_W - PAD - 150; tabs.y = 10; tabs.w = 150;
  panelFlat.add(tabs);

  float bh = 0;
  for (Widget w : bottom) bh += w.h + GAP;
  float bottomY = height - PAD - bh + GAP;
  clipTop = 46;
  clipBottom = bottomY - 42;                       // room for the hint text
  float contentH = 0;
  for (Widget w : top) contentH += w.h + GAP;
  maxScroll = max(0, contentH - (clipBottom - clipTop));
  panelScroll = constrain(panelScroll, 0, maxScroll);
  stack(top, clipTop - panelScroll, true);
  stack(bottom, bottomY, false);
}

void drawPanel() {
  noStroke(); fill(C_PANEL); rect(0, 0, PANEL_W, height);
  clip(0, clipTop - 2, PANEL_W, clipBottom - clipTop + 4);
  for (Widget w : panelFlat) if (w.scrolls) w.display();
  noClip();
  if (maxScroll > 0) {                              // scroll bar
    float track = clipBottom - clipTop, vis = track / (track + maxScroll);
    noStroke(); fill(C_TRACK);
    rect(PANEL_W - 6, clipTop + (track - track * vis) * panelScroll / maxScroll, 3, track * vis, 2);
  }
  fill(C_TEXT); textSize(16); textAlign(LEFT, TOP); text("Generative Line Art", PAD, 14);
  for (Widget w : panelFlat) if (!w.scrolls) w.display();

  fill(C_DIM); textSize(11); textAlign(LEFT, BOTTOM); textLeading(14);
  text("S export | P save preset | L load | N seed | R randomize\nCtrl+Z undo | Ctrl+Y redo | 1-4 layer | arrows = pattern", PAD, clipBottom + 36);

  for (Widget w : panelFlat) if (w instanceof DropdownW) ((DropdownW) w).overlay();
}

String fmtParam(Param p) {
  if (p.isInt) return str(p.i());
  float a = abs(p.val);
  return String.format(Locale.US, a >= 100 ? "%.0f" : (a >= 10 ? "%.1f" : (a >= 1 ? "%.2f" : "%.3f")), p.val);
}

void mousePressed() {
  textFocus = false;
  if (ddOpen) {
    for (Widget w : panelFlat) if (w instanceof DropdownW) ((DropdownW) w).clickItem();
    ddOpen = false;
    return;
  }
  if (mouseX > PANEL_W) return;
  if (mouseButton == RIGHT) {                       // toggle a parameter lock
    for (Widget w : panelFlat) {
      if (w.hit() && lockable(w.p)) {
        w.p.locked = !w.p.locked;
        setStatus(w.p.label + (w.p.locked ? " locked" : " unlocked"));
        break;
      }
    }
    return;
  }
  for (Widget w : panelFlat) {
    if (w.hit()) { activeW = w; activeParam = (w instanceof SliderW) ? w.p : null; w.press(); break; }
  }
}
void mouseDragged() { if (activeW != null) activeW.drag(); }
void mouseReleased() { activeW = null; activeParam = null; }

void mouseWheel(MouseEvent event) {
  if (ddOpen) return;
  for (Widget w : panelFlat) {
    if (w instanceof SliderW && w.hit()) {
      Param p = w.p;
      float step = p.isInt ? 1 : (p.max - p.min) / 100.0;
      p.set(p.val - event.getCount() * step);
      return;
    }
  }
  if (mouseX < PANEL_W) panelScroll = constrain(panelScroll + event.getCount() * 40, 0, maxScroll);
}

// ---------- preview -------------------------------------------------------
void drawPaper() {
  float availW = width - PANEL_W - 80;
  float availH = height - 80 - 24;
  float sc = max(0.1, min(availW / genW, availH / genH));
  int pw = max(1, round(genW * sc)), ph = max(1, round(genH * sc));
  float ox = PANEL_W + (width - PANEL_W - pw) / 2.0;
  float oy = (height - 24 - ph) / 2.0;

  noStroke(); fill(0, 90); rect(ox + 5, oy + 6, pw, ph);
  if (pg == null || pg.width != pw || pg.height != ph || previewStale) renderPreview(pw, ph);
  image(pg, ox, oy);

  float k = pw / genW;
  noFill(); stroke(80, 160, 255, 110); strokeWeight(1);
  rect(ox + xmin * k, oy + ymin * k, (xmax - xmin) * k, (ymax - ymin) * k);
}

void renderPreview(int pw, int ph) {
  if (pg == null || pg.width != pw || pg.height != ph) pg = createGraphics(pw, ph, JAVA2D);
  float k = pw / genW;
  pg.beginDraw();
  pg.background(255);
  pg.noFill();
  pg.strokeJoin(ROUND);
  pg.strokeCap(ROUND);
  for (Layer L : layers) {
    if (!L.pEnabled.on()) continue;
    pg.stroke(L.penColor());
    pg.strokeWeight(max(0.8, L.pPen.val * k));
    for (ArrayList<PVector> path : L.paths) {
      pg.beginShape();
      for (PVector v : path) pg.vertex(v.x * k, v.y * k);
      pg.endShape();
    }
  }
  pg.endDraw();
  previewStale = false;
}

void drawStatusBar() {
  fill(C_PANEL); noStroke(); rect(PANEL_W, height - 24, width - PANEL_W, 24);
  int paths = 0, pts = 0, active = 0; float len = 0, trav = 0, secs = 0;
  for (Layer L : layers) if (L.pEnabled.on()) {
    active++; paths += L.nPaths; pts += L.nPoints; len += L.length; trav += L.travel; secs += L.seconds();
  }
  textSize(12); textAlign(LEFT, CENTER); fill(C_DIM);
  String info = PAPER_NAMES[pPaper.i()] + " " + (int) genW + " x " + (int) genH + " mm  |  "
    + active + (active == 1 ? " layer  |  " : " layers  |  ") + paths + " paths  |  " + pts + " points  |  pen-down "
    + String.format(Locale.US, "%.1f m  |  travel %.1f m  |  plot time ", len / 1000.0, trav / 1000.0) + fmtTime(secs);
  text(info, PANEL_W + 14, height - 12);
  if (millis() - statusMs < 6000) {
    fill(C_ACCENT); textAlign(RIGHT, CENTER);
    text(status, width - 14, height - 12);
  }
}

void setStatus(String s) { status = s; statusMs = millis(); }

String fmtTime(float s) {
  if (s < 60) return "~" + round(s) + " s";
  int m = round(s / 60);
  if (m < 60) return "~" + m + " min";
  return "~" + (m / 60) + " h " + nf(m % 60, 2) + " min";
}

// ---------- geometry generation ------------------------------------------
void generateLayer(Layer L) {
  gen = L;
  noiseSeed(L.pSeed.i());
  randomSeed(L.pSeed.i());
  ArrayList<ArrayList<PVector>> out = new ArrayList<ArrayList<PVector>>();
  switch (L.pMode.i()) {
    case 0:  genFlow(out); break;
    case 1:  genWave(out); break;
    case 2:  genSpiro(out); break;
    case 3:  genRings(out); break;
    case 4:  genLissajous(out); break;
    case 5:  genContour(out); break;
    case 6:  genTruchet(out); break;
    case 7:  genHatch(out); break;
    case 8:  genAttractor(out); break;
    case 9:  genSuper(out); break;
    case 10: genPolygons(out); break;
    case 11: genSpiral(out); break;
    case 12: genMoire(out); break;
    case 13: genPacking(out); break;
    case 14: genHarmonograph(out); break;
    case 15: genHilbert(out); break;
    case 16: genSunburst(out); break;
    case 17: genMaze(out); break;
    case 18: genLSystem(out); break;
    case 19: genGuilloche(out); break;
    case 20: genMaurer(out); break;
    case 21: genPhyllotaxis(out); break;
    case 22: genSubdivision(out); break;
    case 23: genWarpedGrid(out); break;
    case 24: genTree(out); break;
    case 25: genVoronoi(out); break;
    case 26: genImage(out); break;
    case 27: genHexTruchet(out); break;
    case 28: genPenrose(out); break;
    case 29: genHexMaze(out); break;
  }

  // per-layer transform about the centre of the drawing area
  float sc = L.pScale.val, rot = radians(L.pRot.val), ox = L.pOffX.val, oy = L.pOffY.val;
  if (sc != 1 || rot != 0 || ox != 0 || oy != 0) {
    float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2, c = cos(rot), s = sin(rot);
    ArrayList<ArrayList<PVector>> out2 = new ArrayList<ArrayList<PVector>>();
    for (ArrayList<PVector> path : out) {
      ArrayList<PVector> pts = new ArrayList<PVector>(path.size());
      for (PVector v : path) {
        float dx = (v.x - cx) * sc, dy = (v.y - cy) * sc;
        pts.add(new PVector(cx + dx * c - dy * s + ox, cy + dx * s + dy * c + oy));
      }
      emit(out2, pts);
    }
    out = out2;
  }
  if (L.pMask.i() > 0) out = applyMask(out, L.pMask.i() == 1);
  out = cleanUp(out);
  ArrayList<ArrayList<PVector>> ex = extras(L);   // pen test first, so a bad pen shows up straight away
  if (!ex.isEmpty()) { ex.addAll(out); out = ex; }
  L.paths = out;

  L.nPaths = out.size(); L.nPoints = 0; L.length = 0; L.travel = 0;
  float px = 0, py = 0;                            // the plotter starts and ends at the origin
  for (ArrayList<PVector> p : out) {
    L.nPoints += p.size();
    L.length += pathLength(p);
    L.travel += dist(px, py, p.get(0).x, p.get(0).y);
    px = p.get(p.size() - 1).x; py = p.get(p.size() - 1).y;
  }
  L.travel += dist(px, py, 0, 0);
}

float pathLength(ArrayList<PVector> p) {
  float l = 0;
  for (int i = 1; i < p.size(); i++) l += PVector.dist(p.get(i - 1), p.get(i));
  return l;
}

// ---------- path clean-up --------------------------------------------------
// Simplify, drop tiny bits and duplicates, then order (and join) the paths.
ArrayList<ArrayList<PVector>> cleanUp(ArrayList<ArrayList<PVector>> in) {
  float tol = pSimplify.val, minLen = pMinLen.val;
  HashSet<Long> seen = pDedupe.on() ? new HashSet<Long>() : null;
  ArrayList<ArrayList<PVector>> res = new ArrayList<ArrayList<PVector>>(in.size());
  for (ArrayList<PVector> p : in) {
    if (p.size() < 2) continue;
    if (tol > 0 && p.size() > 2) p = simplifyPath(p, tol);
    if (minLen > 0 && pathLength(p) < minLen) continue;
    if (seen != null && !seen.add(pathKey(p))) continue;
    res.add(p);
  }
  return orderPaths(res, pOptimize.on(), pMerge.val);
}

// Direction-independent hash of a path (points rounded to 0.01 mm).
long pathKey(ArrayList<PVector> p) {
  long hf = p.size(), hb = p.size();
  int n = p.size();
  for (int i = 0; i < n; i++) {
    PVector a = p.get(i), b = p.get(n - 1 - i);
    hf = hf * 1000003L + Math.round(a.x * 100) * 31L + Math.round(a.y * 100);
    hb = hb * 1000003L + Math.round(b.x * 100) * 31L + Math.round(b.y * 100);
  }
  return Math.min(hf, hb);
}

// Ramer-Douglas-Peucker: drop points that stay within 'tol' mm of the simplified line.
ArrayList<PVector> simplifyPath(ArrayList<PVector> p, float tol) {
  int n = p.size();
  boolean[] keep = new boolean[n];
  keep[0] = true; keep[n - 1] = true;
  IntList st = new IntList();
  st.append(0); st.append(n - 1);
  while (st.size() > 0) {
    int b = st.remove(st.size() - 1), a = st.remove(st.size() - 1);
    PVector pa = p.get(a), pb = p.get(b);
    float dx = pb.x - pa.x, dy = pb.y - pa.y, ll = dx * dx + dy * dy;
    float best = -1; int bi = -1;
    for (int i = a + 1; i < b; i++) {
      PVector q = p.get(i);
      float d;
      if (ll < 1e-12) d = sq(q.x - pa.x) + sq(q.y - pa.y);
      else {
        float t = constrain(((q.x - pa.x) * dx + (q.y - pa.y) * dy) / ll, 0, 1);
        d = sq(q.x - pa.x - t * dx) + sq(q.y - pa.y - t * dy);
      }
      if (d > best) { best = d; bi = i; }
    }
    if (bi >= 0 && best > tol * tol) {
      keep[bi] = true;
      st.append(a); st.append(bi); st.append(bi); st.append(b);
    }
  }
  ArrayList<PVector> r = new ArrayList<PVector>();
  for (int i = 0; i < n; i++) if (keep[i]) r.add(p.get(i));
  return r;
}

// Greedy nearest-neighbour ordering (paths may be reversed) using a grid of
// path end points, so it stays fast for tens of thousands of paths. Paths
// that start within 'gap' mm of where the previous one ended are joined into
// one stroke. With optimize off the order is kept and only joining happens.
ArrayList<ArrayList<PVector>> orderPaths(ArrayList<ArrayList<PVector>> in, boolean optimize, float gap) {
  int n = in.size();
  ArrayList<ArrayList<PVector>> out = new ArrayList<ArrayList<PVector>>(n);
  if (n == 0) return out;
  float cs = 1, x0 = 0, y0 = 0;
  int gw = 1, gh = 1;
  IntList[] grid = null;
  boolean[] used = new boolean[n];
  if (optimize) {
    x0 = 1e9; y0 = 1e9; float x1 = -1e9, y1 = -1e9;
    for (ArrayList<PVector> p : in) for (int e = 0; e < 2; e++) {
      PVector v = e == 0 ? p.get(0) : p.get(p.size() - 1);
      x0 = min(x0, v.x); y0 = min(y0, v.y); x1 = max(x1, v.x); y1 = max(y1, v.y);
    }
    cs = max(max(0.25, sqrt(max(1, (x1 - x0) * (y1 - y0)) / n)), max(x1 - x0, y1 - y0) / 1000);
    gw = floor((x1 - x0) / cs) + 1; gh = floor((y1 - y0) / cs) + 1;
    grid = new IntList[gw * gh];
    for (int i = 0; i < n; i++) for (int e = 0; e < 2; e++) {
      ArrayList<PVector> p = in.get(i);
      PVector v = e == 0 ? p.get(0) : p.get(p.size() - 1);
      int c = gridCell(v.x, v.y, x0, y0, cs, gw, gh);
      if (grid[c] == null) grid[c] = new IntList();
      grid[c].append(i * 2 + e);
    }
  }
  float cx = 0, cy = 0;
  ArrayList<PVector> last = null;
  for (int k = 0; k < n; k++) {
    int best = k; boolean rev = false;
    if (optimize) {
      best = -1;
      float bd = Float.MAX_VALUE;
      int gx = constrain(floor((cx - x0) / cs), 0, gw - 1), gy = constrain(floor((cy - y0) / cs), 0, gh - 1);
      // lower bound for anything in ring r: (r - 1) cells, or the distance to the grid when starting outside it
      float ox = max(0, max(x0 - cx, cx - (x0 + gw * cs))), oy = max(0, max(y0 - cy, cy - (y0 + gh * cs)));
      float base = sqrt(ox * ox + oy * oy);
      for (int r = 0; r <= max(gw, gh); r++) {
        if (best >= 0 && max(base, (r - 1) * cs) > sqrt(bd)) break;
        for (int j = gy - r; j <= gy + r; j++) {
          if (j < 0 || j >= gh) continue;
          boolean edgeRow = (j == gy - r || j == gy + r);
          for (int i = gx - r; i <= gx + r; i += edgeRow ? 1 : 2 * r) {
            if (i >= 0 && i < gw) {
              IntList l = grid[j * gw + i];
              if (l != null) {
                for (int q = l.size() - 1; q >= 0; q--) {
                  int id = l.get(q);
                  if (used[id >> 1]) { l.remove(q); continue; }
                  ArrayList<PVector> p = in.get(id >> 1);
                  PVector v = (id & 1) == 0 ? p.get(0) : p.get(p.size() - 1);
                  float d = sq(v.x - cx) + sq(v.y - cy);
                  if (d < bd) { bd = d; best = id >> 1; rev = (id & 1) == 1; }
                }
              }
            }
            if (r == 0) break;
          }
        }
      }
    }
    used[best] = true;
    ArrayList<PVector> src = in.get(best);
    ArrayList<PVector> p = new ArrayList<PVector>(src);
    if (rev) Collections.reverse(p);
    PVector s = p.get(0);
    if (last != null && gap > 0 && dist(cx, cy, s.x, s.y) <= gap) {
      if (dist(cx, cy, s.x, s.y) < 1e-4) p.remove(0);
      last.addAll(p);
    } else {
      out.add(p);
      last = p;
    }
    PVector e = last.get(last.size() - 1);
    cx = e.x; cy = e.y;
  }
  return out;
}

int gridCell(float x, float y, float x0, float y0, float cs, int gw, int gh) {
  return constrain(floor((y - y0) / cs), 0, gh - 1) * gw + constrain(floor((x - x0) / cs), 0, gw - 1);
}

// ---------- registration marks / pen test --------------------------------
ArrayList<ArrayList<PVector>> extras(Layer L) {
  ArrayList<ArrayList<PVector>> ex = new ArrayList<ArrayList<PVector>>();
  if (pPenTest.on()) {
    // one small swatch per pen, side by side, centred in the bottom margin
    float s = 6, step = s + 3, band = genH - ymax;
    float x0 = genW / 2 - (NUM_LAYERS * step - 3) / 2 + L.id * step;
    float y0 = band >= s + 2 ? ymax + (band - s) / 2 : genH - s - 1;
    ex.add(rectPath(x0, y0, x0 + s, y0 + s));
    ArrayList<PVector> zig = new ArrayList<PVector>();
    boolean flip = false;
    for (float y = y0 + 0.8; y <= y0 + s - 0.79; y += 0.8) {
      zig.add(new PVector(flip ? x0 + s - 0.8 : x0 + 0.8, y));
      zig.add(new PVector(flip ? x0 + 0.8 : x0 + s - 0.8, y));
      flip = !flip;
    }
    ex.add(zig);
  }
  if (pMarks.on()) {
    // crosshair + circle near each page corner, inside the margin when there is room
    float d = constrain(min(xmin, ymin) / 2, 4, 10), arm = 3;
    float[][] cs = { { d, d }, { genW - d, d }, { d, genH - d }, { genW - d, genH - d } };
    for (float[] c : cs) {
      ArrayList<PVector> hl = new ArrayList<PVector>();
      hl.add(new PVector(c[0] - arm, c[1])); hl.add(new PVector(c[0] + arm, c[1]));
      ArrayList<PVector> vl = new ArrayList<PVector>();
      vl.add(new PVector(c[0], c[1] - arm)); vl.add(new PVector(c[0], c[1] + arm));
      ex.add(hl); ex.add(vl);
      ex.add(circlePath(c[0], c[1], arm * 0.6, 32));
    }
  }
  return ex;
}

// ---------- masks ---------------------------------------------------------
void maskChanged() {
  maskVersion++;
  for (Layer L : layers) if (L.pMask.i() > 0) L.dirty = true;
}

void maskSelected(File f) { if (f != null) pendingMask = f; }

void loadMaskImage(File f) {
  String n = f.getName().toLowerCase();
  try {
    if (n.endsWith(".svg")) { maskSvg = loadShape(f.getAbsolutePath()); maskImg = null; }
    else { maskImg = loadImage(f.getAbsolutePath()); maskSvg = null; }
  } catch (Exception e) { maskImg = null; maskSvg = null; }
  if (maskImg == null && maskSvg == null) { setStatus("Could not read " + f.getName()); maskPath = ""; }
  else { maskPath = f.getAbsolutePath(); pMaskSrc.set(1); setStatus("Mask image: " + f.getName()); }
  maskChanged();
}

// Rasterise the current mask at MASK_K px/mm; rebuilt only when something changed.
void ensureMask() {
  String key = genW + "," + genH + "," + xmin + "," + ymin + "," + xmax + "," + ymax + "," + pMaskSrc.i() + ","
    + pMaskSize.val + "," + pMaskThr.val + "," + pMaskInv.on() + "," + maskVersion;
  if (maskBits != null && key.equals(maskKey)) return;
  maskKey = key;
  maskW = max(1, ceil(genW * MASK_K)); maskH = max(1, ceil(genH * MASK_K));
  PGraphics m = createGraphics(maskW, maskH, JAVA2D);
  float k = MASK_K, ax = xmin * k, ay = ymin * k, aw = (xmax - xmin) * k, ah = (ymax - ymin) * k;
  m.beginDraw();
  m.background(255);
  m.noStroke(); m.fill(0);
  if (pMaskSrc.i() == 0) {
    String t = maskText.replace('|', '\n').trim();
    if (t.length() > 0) {
      String[] lines = split(t, '\n');
      float sz = pMaskSize.val * k;
      m.textFont(maskFont);
      m.textSize(sz);
      float tw = 1;
      for (String l : lines) tw = max(tw, m.textWidth(l));
      float th = lines.length * sz * 1.05;
      sz *= min(1, min(aw * 0.95 / tw, ah * 0.95 / th));   // shrink to fit the drawing area
      m.textSize(sz);
      m.textLeading(sz * 1.05);
      m.textAlign(CENTER, CENTER);
      m.text(t, ax + aw / 2, ay + ah / 2);
    }
  } else if (maskSvg != null || maskImg != null) {
    float sw = maskSvg != null ? maskSvg.width : maskImg.width, sh = maskSvg != null ? maskSvg.height : maskImg.height;
    float sc = min(aw / max(sw, 1), ah / max(sh, 1));
    float dw = sw * sc, dh = sh * sc, dx = ax + (aw - dw) / 2, dy = ay + (ah - dh) / 2;
    if (maskSvg != null) { maskSvg.disableStyle(); m.fill(0); m.noStroke(); m.shape(maskSvg, dx, dy, dw, dh); }
    else m.image(maskImg, dx, dy, dw, dh);
  }
  m.endDraw();
  m.loadPixels();
  float thr = (pMaskSrc.i() == 0 || maskSvg != null) ? 128 : pMaskThr.val * 255;
  boolean inv = pMaskInv.on();
  maskBits = new boolean[maskW * maskH];
  for (int i = 0; i < maskBits.length; i++) {
    int c = m.pixels[i];
    float b = (((c >> 16) & 255) + ((c >> 8) & 255) + (c & 255)) / 3.0;
    maskBits[i] = (b < thr) != inv;
  }
}

boolean maskAt(float x, float y) {
  int ix = (int) (x * MASK_K), iy = (int) (y * MASK_K);
  if (ix < 0 || iy < 0 || ix >= maskW || iy >= maskH) return false;
  return maskBits[iy * maskW + ix];
}

// Keep only the parts of the paths inside (or outside) the mask.
ArrayList<ArrayList<PVector>> applyMask(ArrayList<ArrayList<PVector>> in, boolean inside) {
  ensureMask();
  float stepLen = 0.5 / MASK_K;
  ArrayList<ArrayList<PVector>> res = new ArrayList<ArrayList<PVector>>();
  for (ArrayList<PVector> p : in) {
    PVector a = p.get(0);
    boolean in0 = maskAt(a.x, a.y) == inside;
    ArrayList<PVector> cur = null;
    if (in0) { cur = new ArrayList<PVector>(); cur.add(a.copy()); }
    for (int i = 1; i < p.size(); i++) {
      PVector b = p.get(i);
      a = p.get(i - 1);
      int steps = max(1, ceil(PVector.dist(a, b) / stepLen));
      float pxs = a.x, pys = a.y;
      for (int s = 1; s <= steps; s++) {
        float t = s / (float) steps, x = lerp(a.x, b.x, t), y = lerp(a.y, b.y, t);
        boolean inn = maskAt(x, y) == inside;
        if (inn != in0) {
          PVector q = new PVector((x + pxs) / 2, (y + pys) / 2);
          if (inn) { cur = new ArrayList<PVector>(); cur.add(q); }
          else { cur.add(q); if (cur.size() >= 2) res.add(cur); cur = null; }
          in0 = inn;
        }
        pxs = x; pys = y;
      }
      if (cur != null) cur.add(b.copy());
    }
    if (cur != null && cur.size() >= 2) res.add(cur);
  }
  return res;
}

// Clip a polyline to the margin rectangle and append the pieces to 'out'.
void emit(ArrayList<ArrayList<PVector>> out, ArrayList<PVector> pts) {
  ArrayList<PVector> cur = null;
  for (int i = 0; i < pts.size() - 1; i++) {
    PVector a = pts.get(i), b = pts.get(i + 1);
    float[] c = clipSegment(a.x, a.y, b.x, b.y);
    if (c == null) {
      if (cur != null && cur.size() >= 2) out.add(cur);
      cur = null;
      continue;
    }
    if (cur != null) {
      PVector last = cur.get(cur.size() - 1);
      if (abs(last.x - c[0]) > 1e-3 || abs(last.y - c[1]) > 1e-3) {
        if (cur.size() >= 2) out.add(cur);
        cur = null;
      }
    }
    if (cur == null) { cur = new ArrayList<PVector>(); cur.add(new PVector(c[0], c[1])); }
    cur.add(new PVector(c[2], c[3]));
    if (c[4] < 1) { out.add(cur); cur = null; }   // segment left the rectangle
  }
  if (cur != null && cur.size() >= 2) out.add(cur);
}

// Liang-Barsky segment clipping against the drawing area.
float[] clipSegment(float ax, float ay, float bx, float by) {
  float t0 = 0, t1 = 1, dx = bx - ax, dy = by - ay;
  float[] p = { -dx, dx, -dy, dy };
  float[] q = { ax - xmin, xmax - ax, ay - ymin, ymax - ay };
  for (int i = 0; i < 4; i++) {
    if (p[i] == 0) {
      if (q[i] < 0) return null;
    } else {
      float r = q[i] / p[i];
      if (p[i] < 0) { if (r > t1) return null; if (r > t0) t0 = r; }
      else          { if (r < t0) return null; if (r < t1) t1 = r; }
    }
  }
  return new float[] { ax + t0 * dx, ay + t0 * dy, ax + t1 * dx, ay + t1 * dy, t1 };
}

ArrayList<PVector> circlePath(float cx, float cy, float r, int res) {
  ArrayList<PVector> pts = new ArrayList<PVector>(res + 1);
  for (int i = 0; i <= res; i++) {
    float a = TWO_PI * (i % res) / res;
    pts.add(new PVector(cx + cos(a) * r, cy + sin(a) * r));
  }
  return pts;
}

void arcPath(ArrayList<ArrayList<PVector>> out, float cx, float cy, float r, float a0, float a1) {
  int n = 14;
  ArrayList<PVector> pts = new ArrayList<PVector>(n + 1);
  for (int i = 0; i <= n; i++) {
    float a = lerp(a0, a1, i / (float) n);
    pts.add(new PVector(cx + cos(a) * r, cy + sin(a) * r));
  }
  out.add(pts);
}

// ----- 0: flow field ------
float fNs, fTurb, fRot, fStep, fSep;
int fSteps, fGw, fGh;
int[] fGrid;

void genFlow(ArrayList<ArrayList<PVector>> out) {
  int attempts = (int) pv(0);
  fNs = pv(1) / 100.0; fSteps = (int) pv(2); fStep = pv(3); fTurb = pv(4);
  noiseDetail((int) pv(5), 0.5);
  fRot = radians(pv(6)); fSep = pv(7);
  fGrid = null;
  if (fSep >= 0.3) {
    fGw = ceil((xmax - xmin) / fSep) + 1;
    fGh = ceil((ymax - ymin) / fSep) + 1;
    fGrid = new int[fGw * fGh];
  }
  for (int i = 0; i < attempts; i++) {
    float sx = random(xmin, xmax), sy = random(ymin, ymax);
    int id = i + 1;
    if (fGrid != null && fGrid[flowCell(sx, sy)] != 0) continue;
    ArrayList<PVector> fwd = flowTrace(sx, sy, 1, id);
    ArrayList<PVector> back = flowTrace(sx, sy, -1, id);
    ArrayList<PVector> line = new ArrayList<PVector>();
    for (int k = back.size() - 1; k >= 1; k--) line.add(back.get(k));
    line.addAll(fwd);
    if (line.size() >= 3) out.add(line);
  }
}

int flowCell(float x, float y) {
  int cx = constrain((int) ((x - xmin) / fSep), 0, fGw - 1);
  int cy = constrain((int) ((y - ymin) / fSep), 0, fGh - 1);
  return cy * fGw + cx;
}

ArrayList<PVector> flowTrace(float x, float y, float dir, int id) {
  ArrayList<PVector> pts = new ArrayList<PVector>();
  for (int s = 0; s < fSteps; s++) {
    if (x < xmin || x > xmax || y < ymin || y > ymax) break;
    if (fGrid != null) {
      int c = flowCell(x, y);
      if (fGrid[c] != 0 && fGrid[c] != id) break;
      fGrid[c] = id;
    }
    pts.add(new PVector(x, y));
    float ang = fRot + noise(x * fNs, y * fNs) * TWO_PI * fTurb;
    x += cos(ang) * fStep * dir;
    y += sin(ang) * fStep * dir;
  }
  return pts;
}

// ----- 1: wave lines ------
void genWave(ArrayList<ArrayList<PVector>> out) {
  int n = (int) pv(0), res = (int) pv(1);
  float amp = pv(2), ns = pv(3) / 100.0, drift = pv(4), focus = pv(5);
  boolean hide = pv(6) > 0.5;
  noiseDetail(3, 0.5);

  float w = xmax - xmin, cx = (xmin + xmax) / 2;
  float top = ymin + amp * 0.5, bot = ymax - amp * 0.5;
  if (top > bot) top = bot = (ymin + ymax) / 2;

  float[] sky = new float[res + 1];
  Arrays.fill(sky, Float.MAX_VALUE);
  float[] xs = new float[res + 1], env = new float[res + 1];
  for (int i = 0; i <= res; i++) {
    xs[i] = xmin + w * i / res;
    float g = exp(-sq((xs[i] - cx) / (w * 0.22)));
    env[i] = lerp(1, g, focus);
  }

  for (int j = n - 1; j >= 0; j--) {                    // front (bottom) to back (top)
    float base = n == 1 ? (top + bot) / 2 : lerp(top, bot, j / (float) (n - 1));
    ArrayList<PVector> cur = null;
    for (int i = 0; i <= res; i++) {
      float y = base + (noise(xs[i] * ns, j * drift) - 0.5) * 2 * amp * env[i];
      boolean visible = !hide || y < sky[i];
      if (visible) {
        if (cur == null) cur = new ArrayList<PVector>();
        cur.add(new PVector(xs[i], y));
      } else if (cur != null) {
        emit(out, cur); cur = null;
      }
      if (y < sky[i]) sky[i] = y;
    }
    if (cur != null) emit(out, cur);
  }
}

// ----- 2: spirograph (hypotrochoid) ------
int gcd(int a, int b) { return b == 0 ? a : gcd(b, a % b); }

void genSpiro(ArrayList<ArrayList<PVector>> out) {
  int R = (int) pv(0), r = min((int) pv(1), R - 1);
  float d = pv(2) * r;
  int copies = (int) pv(3);
  float rotStep = radians(pv(4)), shrink = pv(5);

  int revs = r / gcd(R, r);
  float ext = (R - r) + d;
  float base = min(xmax - xmin, ymax - ymin) / 2 / ext;
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  int steps = constrain(revs * 100, 300, 40000);
  double k = (double) (R - r) / r;

  for (int c = 0; c < copies; c++) {
    float s = base * pow(shrink, c);
    float ca = cos(c * rotStep), sa = sin(c * rotStep);
    ArrayList<PVector> pts = new ArrayList<PVector>();
    for (int i = 0; i <= steps; i++) {
      double t = 2 * Math.PI * revs * i / steps;
      float x = (float) ((R - r) * Math.cos(t) + d * Math.cos(k * t));
      float y = (float) ((R - r) * Math.sin(t) - d * Math.sin(k * t));
      pts.add(new PVector(cx + (x * ca - y * sa) * s, cy + (x * sa + y * ca) * s));
    }
    emit(out, pts);
  }
}

// ----- 3: noise rings ------
void genRings(ArrayList<ArrayList<PVector>> out) {
  int n = (int) pv(0), res = (int) pv(1);
  float dist = pv(2), ns = pv(3), drift = pv(4), inner = pv(5);
  noiseDetail(3, 0.5);
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float maxR = max(1, min(xmax - xmin, ymax - ymin) / 2 - dist);

  for (int j = 0; j < n; j++) {
    float t = n == 1 ? 1 : j / (float) (n - 1);
    float r0 = lerp(inner * maxR, maxR, t);
    float k = lerp(0.3, 1, t);
    ArrayList<PVector> pts = new ArrayList<PVector>();
    for (int i = 0; i <= res; i++) {
      float a = TWO_PI * (i % res) / res;                 // i == res closes the loop exactly
      float nv = noise(100 + cos(a) * ns, 100 + sin(a) * ns, j * drift * 0.1);
      float rr = max(0.2, r0 + (nv - 0.5) * 2 * dist * k);
      pts.add(new PVector(cx + cos(a) * rr, cy + sin(a) * rr));
    }
    emit(out, pts);
  }
}

// ----- 4: Lissajous ------
void genLissajous(ArrayList<ArrayList<PVector>> out) {
  int fx = (int) pv(0), fy = (int) pv(1);
  float ph0 = radians(pv(2)), phStep = radians(pv(3));
  int copies = (int) pv(4), res = (int) pv(5);
  float shrink = pv(6);
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float A = (xmax - xmin) / 2, B = (ymax - ymin) / 2;

  for (int c = 0; c < copies; c++) {
    float s = 1 - (copies > 1 ? shrink * c / (copies - 1) : 0);
    float ph = ph0 + c * phStep;
    ArrayList<PVector> pts = new ArrayList<PVector>();
    for (int i = 0; i <= res; i++) {
      float t = TWO_PI * i / res;
      pts.add(new PVector(cx + A * s * sin(fx * t + ph), cy + B * s * sin(fy * t)));
    }
    emit(out, pts);
  }
}

// ----- 5: contour map (marching squares on a noise field) ------
int[] mS0, mS1, mSa, mSb;
float[] mEx, mEy;
boolean[] mVis;
int mNs;

void genContour(ArrayList<ArrayList<PVector>> out) {
  int levels = (int) pv(0), res = (int) pv(1);
  float ns = pv(2) / 100.0, warp = pv(4), island = pv(5);
  int oct = (int) pv(3);
  boolean ridged = pv(6) > 0.5;
  noiseDetail(oct, 0.5);

  float w = xmax - xmin, h = ymax - ymin;
  float cs = max(w, h) / res;
  int gx = ceil(w / cs), gy = ceil(h / cs);
  int vw = gx + 1, vh = gy + 1;
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;

  float[] f = new float[vw * vh];
  float mn = 1e9, mx = -1e9;
  for (int j = 0; j < vh; j++) {
    for (int i = 0; i < vw; i++) {
      float x = xmin + i * cs, y = ymin + j * cs;
      float sx = x * ns, sy = y * ns;
      if (warp > 0) {
        sx += (noise(sx + 31.7, sy + 11.3) - 0.5) * warp * 4;
        sy += (noise(sx + 77.1, sy + 53.9) - 0.5) * warp * 4;
      }
      float v = noise(sx, sy);
      if (ridged) v = 1 - abs(2 * v - 1);
      if (island > 0) {
        float dx = (x - cx) / (w * 0.5), dy = (y - cy) / (h * 0.5);
        v -= island * (dx * dx + dy * dy) * 0.5;
      }
      f[j * vw + i] = v;
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
  }

  int nEdges = 2 * vw * vh;
  mS0 = new int[nEdges]; mS1 = new int[nEdges];
  mEx = new float[nEdges]; mEy = new float[nEdges];
  mSa = new int[2 * gx * gy + 2]; mSb = new int[2 * gx * gy + 2];
  mVis = new boolean[2 * gx * gy + 2];

  for (int k = 0; k < levels; k++) {
    float lv = mn + (k + 1) * (mx - mn) / (levels + 1);
    marchLevel(f, vw, gx, gy, cs, lv, out);
  }
}

void addSeg(int a, int b) {
  mSa[mNs] = a; mSb[mNs] = b;
  if (mS0[a] < 0) mS0[a] = mNs; else mS1[a] = mNs;
  if (mS0[b] < 0) mS0[b] = mNs; else mS1[b] = mNs;
  mNs++;
}

void marchLevel(float[] f, int vw, int gx, int gy, float cs, float lv, ArrayList<ArrayList<PVector>> out) {
  int nEdges = 2 * vw * (gy + 1);
  Arrays.fill(mS0, 0, nEdges, -1);
  Arrays.fill(mS1, 0, nEdges, -1);
  mNs = 0;

  for (int j = 0; j < gy; j++) {
    for (int i = 0; i < gx; i++) {
      int i0 = j * vw + i;
      float v0 = f[i0], v1 = f[i0 + 1], v2 = f[i0 + vw + 1], v3 = f[i0 + vw];
      int c = (v0 > lv ? 1 : 0) | (v1 > lv ? 2 : 0) | (v2 > lv ? 4 : 0) | (v3 > lv ? 8 : 0);
      if (c == 0 || c == 15) continue;
      int eT = 2 * i0, eR = 2 * (i0 + 1) + 1, eB = 2 * (i0 + vw), eL = 2 * i0 + 1;
      float x0 = xmin + i * cs, y0 = ymin + j * cs;
      if ((v0 > lv) != (v1 > lv)) { mEx[eT] = x0 + cs * (lv - v0) / (v1 - v0); mEy[eT] = y0; }
      if ((v1 > lv) != (v2 > lv)) { mEx[eR] = x0 + cs;                          mEy[eR] = y0 + cs * (lv - v1) / (v2 - v1); }
      if ((v3 > lv) != (v2 > lv)) { mEx[eB] = x0 + cs * (lv - v3) / (v2 - v3); mEy[eB] = y0 + cs; }
      if ((v0 > lv) != (v3 > lv)) { mEx[eL] = x0;                               mEy[eL] = y0 + cs * (lv - v0) / (v3 - v0); }
      switch (c) {
        case 1: case 14: addSeg(eL, eT); break;
        case 2: case 13: addSeg(eT, eR); break;
        case 3: case 12: addSeg(eL, eR); break;
        case 4: case 11: addSeg(eR, eB); break;
        case 6: case 9:  addSeg(eT, eB); break;
        case 7: case 8:  addSeg(eL, eB); break;
        case 5: {
          boolean ctr = (v0 + v1 + v2 + v3) * 0.25 > lv;
          if (ctr) { addSeg(eT, eR); addSeg(eB, eL); } else { addSeg(eL, eT); addSeg(eR, eB); }
          break;
        }
        case 10: {
          boolean ctr = (v0 + v1 + v2 + v3) * 0.25 > lv;
          if (ctr) { addSeg(eL, eT); addSeg(eR, eB); } else { addSeg(eT, eR); addSeg(eB, eL); }
          break;
        }
      }
    }
  }

  // stitch the little segments into long polylines
  Arrays.fill(mVis, 0, mNs, false);
  for (int s0 = 0; s0 < mNs; s0++) {
    if (mVis[s0]) continue;
    mVis[s0] = true;
    ArrayList<Integer> fw = new ArrayList<Integer>(), bk = new ArrayList<Integer>();
    boolean closed = false;
    int seg = s0, e = mSb[s0];
    while (true) {
      fw.add(e);
      int nx = (mS0[e] == seg) ? mS1[e] : mS0[e];
      if (nx < 0) break;
      if (nx == s0) { closed = true; break; }
      if (mVis[nx]) break;
      mVis[nx] = true; seg = nx;
      e = (mSa[nx] == e) ? mSb[nx] : mSa[nx];
    }
    if (!closed) {
      seg = s0; e = mSa[s0];
      while (true) {
        bk.add(e);
        int nx = (mS0[e] == seg) ? mS1[e] : mS0[e];
        if (nx < 0 || mVis[nx]) break;
        mVis[nx] = true; seg = nx;
        e = (mSa[nx] == e) ? mSb[nx] : mSa[nx];
      }
    }
    ArrayList<PVector> pts = new ArrayList<PVector>(bk.size() + fw.size() + 1);
    for (int k = bk.size() - 1; k >= 0; k--) pts.add(new PVector(mEx[bk.get(k)], mEy[bk.get(k)]));
    for (int k = 0; k < fw.size(); k++) pts.add(new PVector(mEx[fw.get(k)], mEy[fw.get(k)]));
    if (closed) pts.add(pts.get(0).copy());
    if (pts.size() >= 2) emit(out, pts);
  }
}

// ----- 6: truchet tiles ------
void genTruchet(ArrayList<ArrayList<PVector>> out) {
  int n = (int) pv(0), style = (int) pv(1), lines = (int) pv(2);
  float bias = pv(3), inset = pv(4);
  float w = xmax - xmin, h = ymax - ymin;
  float s = min(w, h) / n;
  int nx = max(1, floor(w / s)), ny = max(1, floor(h / s));
  float ox = xmin + (w - nx * s) / 2, oy = ymin + (h - ny * s) / 2;

  for (int j = 0; j < ny; j++) {
    for (int i = 0; i < nx; i++) {
      boolean flip = random(1) > bias;
      float x = ox + i * s, y = oy + j * s;
      if (style == 0) {                                   // quarter-circle arcs
        for (int k = 0; k < lines; k++) {
          float r = s * (0.5 + (k - (lines - 1) / 2.0) * 0.8 * (1 - inset) / max(1, lines));
          if (!flip) { arcPath(out, x, y, r, 0, HALF_PI); arcPath(out, x + s, y + s, r, PI, PI + HALF_PI); }
          else       { arcPath(out, x + s, y, r, HALF_PI, PI); arcPath(out, x, y + s, r, PI + HALF_PI, TWO_PI); }
        }
      } else if (style == 1) {                            // parallel diagonals
        for (int k = 0; k < lines; k++) {
          float d = (k - (lines - 1) / 2.0) * s * (1 - inset) / lines;
          float xa = max(0, -d), xb = min(s, s - d);
          if (xa >= xb) continue;
          float ya = xa + d, yb = xb + d;
          ArrayList<PVector> pts = new ArrayList<PVector>();
          pts.add(new PVector(x + (flip ? s - xa : xa), y + ya));
          pts.add(new PVector(x + (flip ? s - xb : xb), y + yb));
          out.add(pts);
        }
      } else {                                            // fans from a corner
        int m = lines * 2;
        float cx = flip ? x + s : x, cy = y;
        for (int q = 0; q < m; q++) {
          float u = (q + 0.5) / m;
          ArrayList<PVector> a = new ArrayList<PVector>();
          a.add(new PVector(cx, cy)); a.add(new PVector(flip ? x + s - s * u : x + s * u, y + s));
          out.add(a);
          ArrayList<PVector> b = new ArrayList<PVector>();
          b.add(new PVector(cx, cy)); b.add(new PVector(flip ? x : x + s, y + s * u));
          out.add(b);
        }
      }
    }
  }
}

// ----- 7: hatch shading ------
void genHatch(ArrayList<ArrayList<PVector>> out) {
  float sp = pv(0), ang0 = radians(pv(1));
  int passes = (int) pv(2);
  float step = radians(pv(3)), ns = pv(4) / 100.0, cover = pv(5), vig = pv(6);
  noiseDetail(3, 0.5);
  float w = xmax - xmin, h = ymax - ymin;
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float R = 0.5 * sqrt(w * w + h * h) + 1;
  float lo0 = 0.2 + 0.6 * (1 - cover);

  for (int p = 0; p < passes; p++) {
    float a = ang0 + p * step;
    float ux = cos(a), uy = sin(a), nx = -uy, ny = ux;
    float lo = lo0 + p * (0.8 - lo0) / passes;
    for (float off = -R; off <= R; off += sp) {
      PVector runStart = null, runEnd = null;
      for (float t = -R; t <= R; t += 0.8) {
        float x = cx + ux * t + nx * off, y = cy + uy * t + ny * off;
        boolean ok = x >= xmin && x <= xmax && y >= ymin && y <= ymax;
        if (ok) {
          float d = noise(x * ns, y * ns);
          if (vig > 0) {
            float rn = sqrt(sq((x - cx) / (w * 0.5)) + sq((y - cy) / (h * 0.5)));
            d -= vig * 0.5 * rn;
          }
          ok = d > lo;
        }
        if (ok) {
          if (runStart == null) runStart = new PVector(x, y);
          runEnd = new PVector(x, y);
        } else if (runStart != null) {
          if (PVector.dist(runStart, runEnd) > 0.5) { ArrayList<PVector> l = new ArrayList<PVector>(); l.add(runStart); l.add(runEnd); out.add(l); }
          runStart = null;
        }
      }
      if (runStart != null && PVector.dist(runStart, runEnd) > 0.5) { ArrayList<PVector> l = new ArrayList<PVector>(); l.add(runStart); l.add(runEnd); out.add(l); }
    }
  }
}

// ----- 8: strange attractors ------
void genAttractor(ArrayList<ArrayList<PVector>> out) {
  int type = (int) pv(0);
  float a = pv(1), b = pv(2), c = pv(3), d = pv(4);
  int iters = (int) pv(5), strands = (int) pv(6);

  // probe run to find the extent of the attractor
  float x = 0.1, y = 0.1;
  float x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
  for (int i = 0; i < 4000; i++) {
    float nx, ny;
    if (type == 0) { nx = sin(a * y) + c * cos(a * x); ny = sin(b * x) + d * cos(b * y); }
    else           { nx = sin(a * y) - cos(b * x);     ny = sin(c * x) - cos(d * y); }
    x = nx; y = ny;
    if (i > 100) { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y); }
  }
  float sw = max(x1 - x0, 1e-3), sh = max(y1 - y0, 1e-3);
  float w = xmax - xmin, h = ymax - ymin;
  float sc = min(w / sw, h / sh) * 0.98;
  float cx = (xmin + xmax) / 2 - (x0 + x1) / 2 * sc, cy = (ymin + ymax) / 2 - (y0 + y1) / 2 * sc;

  int per = max(2, iters / strands);
  for (int sIdx = 0; sIdx < strands; sIdx++) {
    x = random(-1, 1); y = random(-1, 1);
    ArrayList<PVector> pts = new ArrayList<PVector>(per);
    for (int i = 0; i < per + 50; i++) {
      float nx, ny;
      if (type == 0) { nx = sin(a * y) + c * cos(a * x); ny = sin(b * x) + d * cos(b * y); }
      else           { nx = sin(a * y) - cos(b * x);     ny = sin(c * x) - cos(d * y); }
      x = nx; y = ny;
      if (i >= 50) pts.add(new PVector(cx + x * sc, cy + y * sc));
    }
    emit(out, pts);
  }
}

// ----- 9: superformula ------
float superR(float phi, float m, float n1, float n2, float n3) {
  float t1 = pow(abs(cos(m * phi / 4)), n2);
  float t2 = pow(abs(sin(m * phi / 4)), n3);
  return pow(t1 + t2, -1.0 / n1);
}

void genSuper(ArrayList<ArrayList<PVector>> out) {
  int n = (int) pv(0);
  float m = pv(1), n1 = pv(2), n2 = pv(3), n3 = pv(4), inner = pv(5), twist = radians(pv(6));
  int res = (int) pv(7);
  float range = (((int) m) % 2 == 0) ? TWO_PI : 2 * TWO_PI;     // odd m needs two turns to close
  float rmax = 1e-6;
  for (int i = 0; i < 720; i++) rmax = max(rmax, superR(range * i / 720.0, m, n1, n2, n3));
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float R = min(xmax - xmin, ymax - ymin) / 2;

  for (int k = 0; k < n; k++) {
    float t = n == 1 ? 0 : k / (float) (n - 1);
    float s = lerp(1, inner, t) * R / rmax;
    float rot = twist * t;
    ArrayList<PVector> pts = new ArrayList<PVector>();
    for (int i = 0; i <= res; i++) {
      float phi = range * i / res;
      float r = superR(phi, m, n1, n2, n3) * s;
      float ang = phi + rot;
      pts.add(new PVector(cx + cos(ang) * r, cy + sin(ang) * r));
    }
    emit(out, pts);
  }
}

// ----- 10: nested polygons ------
void genPolygons(ArrayList<ArrayList<PVector>> out) {
  int sides = (int) pv(0), layersN = (int) pv(1);
  float twist = radians(pv(2)), shrink = pv(3), dx = pv(4), dy = pv(5);
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float R0 = min(xmax - xmin, ymax - ymin) / 2;
  for (int k = 0; k < layersN; k++) {
    float r = R0 * pow(shrink, k), rot = k * twist - HALF_PI;
    ArrayList<PVector> pts = new ArrayList<PVector>();
    for (int i = 0; i <= sides; i++) {
      float a = rot + TWO_PI * (i % sides) / sides;
      pts.add(new PVector(cx + k * dx + cos(a) * r, cy + k * dy + sin(a) * r));
    }
    emit(out, pts);
  }
}

// ----- 11: spiral ------
void genSpiral(ArrayList<ArrayList<PVector>> out) {
  int turns = (int) pv(0), arms = (int) pv(1), ppt = (int) pv(2);
  float wob = pv(3), wns = pv(4), fit = pv(5), hole = pv(6);
  noiseDetail(3, 0.5);
  float w = xmax - xmin, h = ymax - ymin;
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float Rc = min(w, h) / 2;
  int total = turns * ppt;
  for (int arm = 0; arm < arms; arm++) {
    ArrayList<PVector> pts = new ArrayList<PVector>(total + 1);
    for (int i = 0; i <= total; i++) {
      float t = i / (float) total;
      float th = TWO_PI * turns * t + arm * TWO_PI / arms;
      float rect = min((w / 2) / max(abs(cos(th)), 1e-4), (h / 2) / max(abs(sin(th)), 1e-4));
      float Rmax = lerp(Rc, rect, fit);
      float r = Rmax * (hole + (1 - hole) * t);
      if (wob > 0) r += (noise(50 + cos(th) * wns, 50 + sin(th) * wns, t * 3) - 0.5) * 2 * wob;
      pts.add(new PVector(cx + cos(th) * r, cy + sin(th) * r));
    }
    emit(out, pts);
  }
}

// ----- 12: moire circles ------
void genMoire(ArrayList<ArrayList<PVector>> out) {
  int sets = (int) pv(0), rings = (int) pv(1), res = (int) pv(5);
  float spacing = pv(2), spread = pv(3), rot = radians(pv(4));
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  for (int s = 0; s < sets; s++) {
    float a = rot + s * TWO_PI / sets;
    float ccx = cx + cos(a) * spread, ccy = cy + sin(a) * spread;
    for (int k = 1; k <= rings; k++) emit(out, circlePath(ccx, ccy, k * spacing, res));
  }
}

// ----- 13: circle packing ------
void genPacking(ArrayList<ArrayList<PVector>> out) {
  int attempts = (int) pv(0);
  float rmin = pv(1), rmax = max(pv(2), pv(1)), pad = pv(3), gap = pv(4);
  ArrayList<float[]> cs = new ArrayList<float[]>();
  for (int a = 0; a < attempts; a++) {
    float x = random(xmin + rmin, max(xmin + rmin, xmax - rmin));
    float y = random(ymin + rmin, max(ymin + rmin, ymax - rmin));
    float r = min(rmax, min(min(x - xmin, xmax - x), min(y - ymin, ymax - y)));
    for (float[] c : cs) {
      float dd = dist(x, y, c[0], c[1]) - c[2] - pad;
      if (dd < r) { r = dd; if (r < rmin) break; }
    }
    if (r >= rmin) cs.add(new float[] { x, y, r });
  }
  for (float[] c : cs) {
    int res = constrain((int) (c[2] * 8), 16, 120);
    if (gap <= 0) out.add(circlePath(c[0], c[1], c[2], res));
    else for (float r = c[2]; r >= max(gap * 0.5, 0.3); r -= gap) out.add(circlePath(c[0], c[1], r, res));
  }
}

// ----- 14: harmonograph ------
void genHarmonograph(ArrayList<ArrayList<PVector>> out) {
  int fx = (int) pv(0), fy = (int) pv(1);
  float dx = pv(2), dy = pv(3), phase = radians(pv(4)), damp = pv(5), dur = pv(6);
  int steps = (int) pv(7);
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float R = min(xmax - xmin, ymax - ymin) / 2;
  ArrayList<PVector> pts = new ArrayList<PVector>(steps + 1);
  for (int i = 0; i <= steps; i++) {
    float t = dur * i / steps;
    float e = exp(-damp * t);
    float x = 0.5 * (sin(fx * t + phase) + sin((fx + dx) * t)) * e;
    float y = 0.5 * (sin(fy * t) + sin((fy + dy) * t + phase * 0.5)) * e;
    pts.add(new PVector(cx + x * R, cy + y * R));
  }
  emit(out, pts);
}

// ----- 15: Hilbert curve ------
void genHilbert(ArrayList<ArrayList<PVector>> out) {
  int order = (int) pv(0), smooth = (int) pv(1);
  float jitter = pv(2);
  boolean stretch = pv(3) > 0.5;
  int n = 1 << order, total = n * n;
  float w = xmax - xmin, h = ymax - ymin;
  float sx = stretch ? w / n : min(w, h) / n, sy = stretch ? h / n : min(w, h) / n;
  float ox = xmin + (w - sx * n) / 2, oy = ymin + (h - sy * n) / 2;
  ArrayList<PVector> pts = new ArrayList<PVector>(total);
  for (int d = 0; d < total; d++) {
    int[] xy = hilbertD2XY(n, d);
    float jx = jitter > 0 ? (random(1) - 0.5) * jitter * sx : 0, jy = jitter > 0 ? (random(1) - 0.5) * jitter * sy : 0;
    pts.add(new PVector(ox + (xy[0] + 0.5) * sx + jx, oy + (xy[1] + 0.5) * sy + jy));
  }
  emit(out, chaikin(pts, smooth));
}

int[] hilbertD2XY(int n, int d) {
  int x = 0, y = 0, t = d;
  for (int s = 1; s < n; s *= 2) {
    int rx = 1 & (t / 2);
    int ry = 1 & (t ^ rx);
    if (ry == 0) {
      if (rx == 1) { x = s - 1 - x; y = s - 1 - y; }
      int tmp = x; x = y; y = tmp;
    }
    x += s * rx; y += s * ry;
    t /= 4;
  }
  return new int[] { x, y };
}

// ----- 16: sunburst ------
void genSunburst(ArrayList<ArrayList<PVector>> out) {
  int rays = (int) pv(0);
  float innerR = pv(1), lenVar = pv(2), ns = pv(3), twist = radians(pv(4)), innerVar = pv(5);
  noiseDetail(3, 0.5);
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float R = min(xmax - xmin, ymax - ymin) / 2;
  for (int i = 0; i < rays; i++) {
    float a = TWO_PI * i / rays;
    float q = constrain(map(noise(200 + cos(a) * ns, 200 + sin(a) * ns), 0.25, 0.75, 0, 1), 0, 1);
    float q2 = constrain(map(noise(400 + cos(a) * ns, 400 + sin(a) * ns), 0.25, 0.75, 0, 1), 0, 1);
    float rout = R * lerp(1 - lenVar, 1, q);
    float rin = R * innerR * lerp(1, q2, innerVar);
    if (rout <= rin + 0.5) continue;
    ArrayList<PVector> pts = new ArrayList<PVector>();
    for (int k = 0; k <= 24; k++) {
      float t = k / 24.0;
      float r = lerp(rin, rout, t), ang = a + twist * t;
      pts.add(new PVector(cx + cos(ang) * r, cy + sin(ang) * r));
    }
    emit(out, pts);
  }
}

// ---------- helpers for the patterns below --------------------------------

// Chaikin corner cutting on an open polyline (end points are kept).
ArrayList<PVector> chaikin(ArrayList<PVector> pts, int iters) {
  for (int it = 0; it < iters && pts.size() >= 3 && pts.size() < 150000; it++) {
    ArrayList<PVector> np = new ArrayList<PVector>(pts.size() * 2);
    np.add(pts.get(0));
    for (int i = 0; i < pts.size() - 1; i++) {
      PVector p0 = pts.get(i), p1 = pts.get(i + 1);
      np.add(new PVector(lerp(p0.x, p1.x, 0.25), lerp(p0.y, p1.y, 0.25)));
      np.add(new PVector(lerp(p0.x, p1.x, 0.75), lerp(p0.y, p1.y, 0.75)));
    }
    np.add(pts.get(pts.size() - 1));
    pts = np;
  }
  return pts;
}

// Chaikin on a closed polygon given without the repeated first point.
// Returns a closed polyline (first point repeated at the end).
ArrayList<PVector> chaikinClosed(ArrayList<PVector> poly, int iters) {
  for (int it = 0; it < iters && poly.size() < 50000; it++) {
    int n = poly.size();
    ArrayList<PVector> np = new ArrayList<PVector>(n * 2);
    for (int i = 0; i < n; i++) {
      PVector p0 = poly.get(i), p1 = poly.get((i + 1) % n);
      np.add(new PVector(lerp(p0.x, p1.x, 0.25), lerp(p0.y, p1.y, 0.25)));
      np.add(new PVector(lerp(p0.x, p1.x, 0.75), lerp(p0.y, p1.y, 0.75)));
    }
    poly = np;
  }
  ArrayList<PVector> closed = new ArrayList<PVector>(poly);
  if (!poly.isEmpty()) closed.add(poly.get(0).copy());
  return closed;
}

// Scale paths built in arbitrary units uniformly into the drawing area (centred).
void fitPaths(ArrayList<ArrayList<PVector>> raw, ArrayList<ArrayList<PVector>> out) {
  float x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  for (ArrayList<PVector> p : raw) for (PVector v : p) {
    x0 = min(x0, v.x); x1 = max(x1, v.x); y0 = min(y0, v.y); y1 = max(y1, v.y);
  }
  if (x0 > x1) return;
  float sc = min((xmax - xmin) / max(x1 - x0, 1e-6), (ymax - ymin) / max(y1 - y0, 1e-6));
  float ox = (xmin + xmax) / 2 - (x0 + x1) / 2 * sc, oy = (ymin + ymax) / 2 - (y0 + y1) / 2 * sc;
  for (ArrayList<PVector> p : raw) {
    ArrayList<PVector> pts = new ArrayList<PVector>(p.size());
    for (PVector v : p) pts.add(new PVector(ox + v.x * sc, oy + v.y * sc));
    emit(out, pts);
  }
}

// Joins loose segments {x0, y0, x1, y1} into as few polylines as possible:
// end points closer than 0.02 mm are merged, duplicate segments are dropped
// and at junctions the straightest continuation wins. Saves many pen lifts
// on grid- and cell-like patterns.
void chainSegments(ArrayList<float[]> segs, ArrayList<ArrayList<PVector>> out) {
  final float eps = 0.02;
  ArrayList<PVector> verts = new ArrayList<PVector>();
  HashMap<Long, IntList> bins = new HashMap<Long, IntList>();
  IntList ea = new IntList(), eb = new IntList();
  HashSet<Long> seen = new HashSet<Long>();
  ArrayList<IntList> adj = new ArrayList<IntList>();
  for (float[] s : segs) {
    int a = vertexId(verts, bins, adj, s[0], s[1], eps), b = vertexId(verts, bins, adj, s[2], s[3], eps);
    if (a == b) continue;
    long key = ((long) min(a, b) << 32) | max(a, b);
    if (!seen.add(key)) continue;
    adj.get(a).append(ea.size()); adj.get(b).append(ea.size());
    ea.append(a); eb.append(b);
  }
  boolean[] used = new boolean[ea.size()];
  for (int pass = 0; pass < 2; pass++) {             // start at loose ends first, then close loops
    for (int v = 0; v < verts.size(); v++) {
      if (pass == 0 && adj.get(v).size() % 2 == 0) continue;
      while (true) {
        ArrayList<PVector> pts = new ArrayList<PVector>();
        pts.add(verts.get(v).copy());
        int cur = v; float dx = 0, dy = 0;
        while (true) {
          int best = -1; float bs = -1e9;
          PVector a = verts.get(cur);
          IntList es = adj.get(cur);
          for (int k = 0; k < es.size(); k++) {
            int e = es.get(k);
            if (used[e]) continue;
            PVector b = verts.get(ea.get(e) == cur ? eb.get(e) : ea.get(e));
            float l = max(dist(a.x, a.y, b.x, b.y), 1e-9);
            float sc = (dx * (b.x - a.x) + dy * (b.y - a.y)) / l;
            if (sc > bs) { bs = sc; best = e; }
          }
          if (best < 0) break;
          used[best] = true;
          int o = ea.get(best) == cur ? eb.get(best) : ea.get(best);
          PVector b = verts.get(o);
          float l = max(dist(a.x, a.y, b.x, b.y), 1e-9);
          dx = (b.x - a.x) / l; dy = (b.y - a.y) / l;
          pts.add(b.copy());
          cur = o;
        }
        if (pts.size() < 2) break;
        emit(out, pts);
      }
    }
  }
}

int vertexId(ArrayList<PVector> verts, HashMap<Long, IntList> bins, ArrayList<IntList> adj, float x, float y, float eps) {
  long bx = (long) Math.floor(x / eps), by = (long) Math.floor(y / eps);
  for (long i = bx - 1; i <= bx + 1; i++) {
    for (long j = by - 1; j <= by + 1; j++) {
      IntList l = bins.get((i << 32) ^ (j & 0xffffffffL));
      if (l == null) continue;
      for (int k = 0; k < l.size(); k++) {
        PVector v = verts.get(l.get(k));
        if (abs(v.x - x) <= eps && abs(v.y - y) <= eps) return l.get(k);
      }
    }
  }
  long key = (bx << 32) ^ (by & 0xffffffffL);
  IntList l = bins.get(key);
  if (l == null) { l = new IntList(); bins.put(key, l); }
  l.append(verts.size());
  verts.add(new PVector(x, y));
  adj.add(new IntList());
  return verts.size() - 1;
}

// Serpentine hatch of an axis-aligned rectangle: one continuous zigzag stroke.
void hatchRect(ArrayList<ArrayList<PVector>> out, float x0, float y0, float x1, float y1, float ang, float sp) {
  if (x1 - x0 < 0.3 || y1 - y0 < 0.3) return;
  float ux = cos(ang), uy = sin(ang), nx = -uy, ny = ux;
  float cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, R = 0.5 * dist(x0, y0, x1, y1);
  ArrayList<PVector> zig = new ArrayList<PVector>();
  boolean flip = false;
  int kmax = floor(R / sp);
  for (int k = -kmax; k <= kmax; k++) {
    float px = cx + nx * k * sp, py = cy + ny * k * sp;
    float tmin = -1e9, tmax = 1e9;
    if (abs(ux) < 1e-6) { if (px < x0 || px > x1) continue; }
    else { float ta = (x0 - px) / ux, tb = (x1 - px) / ux; tmin = max(tmin, min(ta, tb)); tmax = min(tmax, max(ta, tb)); }
    if (abs(uy) < 1e-6) { if (py < y0 || py > y1) continue; }
    else { float ta = (y0 - py) / uy, tb = (y1 - py) / uy; tmin = max(tmin, min(ta, tb)); tmax = min(tmax, max(ta, tb)); }
    if (tmax - tmin < 0.05) continue;
    PVector a = new PVector(px + ux * tmin, py + uy * tmin), b = new PVector(px + ux * tmax, py + uy * tmax);
    if (flip) { zig.add(b); zig.add(a); } else { zig.add(a); zig.add(b); }
    flip = !flip;
  }
  if (zig.size() >= 2) emit(out, zig);
}

ArrayList<PVector> rectPath(float x0, float y0, float x1, float y1) {
  ArrayList<PVector> r = new ArrayList<PVector>();
  r.add(new PVector(x0, y0)); r.add(new PVector(x1, y0)); r.add(new PVector(x1, y1));
  r.add(new PVector(x0, y1)); r.add(new PVector(x0, y0));
  return r;
}

// ----- 17: maze (recursive backtracker) ------
void genMaze(ArrayList<ArrayList<PVector>> out) {
  int cells = (int) pv(0), style = (int) pv(1);
  float straight = pv(2), loops = pv(3);
  boolean doors = pv(4) > 0.5;
  float w = xmax - xmin, h = ymax - ymin;
  float s = min(w, h) / cells;
  int nx = max(1, floor(w / s + 1e-3)), ny = max(1, floor(h / s + 1e-3));
  float ox = xmin + (w - nx * s) / 2, oy = ymin + (h - ny * s) / 2;

  // hW[j * nx + i]: wall above cell (i, j), j = 0..ny.  vW[j * (nx + 1) + i]: wall left of cell (i, j), i = 0..nx
  boolean[] hW = new boolean[(ny + 1) * nx], vW = new boolean[ny * (nx + 1)];
  Arrays.fill(hW, true); Arrays.fill(vW, true);
  int[] DX = { 1, 0, -1, 0 }, DY = { 0, 1, 0, -1 };
  boolean[] vis = new boolean[nx * ny];
  int[] stack = new int[nx * ny], lastDir = new int[nx * ny], cand = new int[4];
  int sp = 0, start = (int) random(nx * ny);
  vis[start] = true; stack[sp++] = start; lastDir[start] = (int) random(4);
  while (sp > 0) {
    int c = stack[sp - 1], ci = c % nx, cj = c / nx, nc = 0;
    boolean straightOk = false;
    for (int d = 0; d < 4; d++) {
      int ni = ci + DX[d], nj = cj + DY[d];
      if (ni < 0 || nj < 0 || ni >= nx || nj >= ny || vis[nj * nx + ni]) continue;
      cand[nc++] = d;
      if (d == lastDir[c]) straightOk = true;
    }
    if (nc == 0) { sp--; continue; }
    int d = (straightOk && random(1) < straight) ? lastDir[c] : cand[(int) random(nc)];
    if (d == 0) vW[cj * (nx + 1) + ci + 1] = false;
    else if (d == 2) vW[cj * (nx + 1) + ci] = false;
    else if (d == 1) hW[(cj + 1) * nx + ci] = false;
    else hW[cj * nx + ci] = false;
    int n = (cj + DY[d]) * nx + ci + DX[d];
    vis[n] = true; lastDir[n] = d; stack[sp++] = n;
  }
  if (loops > 0) {                                     // knock out extra walls -> multiple routes
    for (int j = 1; j < ny; j++) for (int i = 0; i < nx; i++) if (hW[j * nx + i] && random(1) < loops * 0.3) hW[j * nx + i] = false;
    for (int j = 0; j < ny; j++) for (int i = 1; i < nx; i++) if (vW[j * (nx + 1) + i] && random(1) < loops * 0.3) vW[j * (nx + 1) + i] = false;
  }
  if (doors) { hW[0] = false; hW[ny * nx + nx - 1] = false; }

  ArrayList<float[]> segs = new ArrayList<float[]>();
  if (style == 0) {
    for (int j = 0; j <= ny; j++) for (int i = 0; i < nx; i++)
      if (hW[j * nx + i]) segs.add(new float[] { ox + i * s, oy + j * s, ox + (i + 1) * s, oy + j * s });
    for (int j = 0; j < ny; j++) for (int i = 0; i <= nx; i++)
      if (vW[j * (nx + 1) + i]) segs.add(new float[] { ox + i * s, oy + j * s, ox + i * s, oy + (j + 1) * s });
  } else {
    for (int j = 0; j < ny; j++) {
      for (int i = 0; i < nx; i++) {
        float x = ox + (i + 0.5) * s, y = oy + (j + 0.5) * s;
        if (i + 1 < nx && !vW[j * (nx + 1) + i + 1]) segs.add(new float[] { x, y, x + s, y });
        if (j + 1 < ny && !hW[(j + 1) * nx + i]) segs.add(new float[] { x, y, x, y + s });
      }
    }
    if (doors) {
      segs.add(new float[] { ox + 0.5 * s, oy, ox + 0.5 * s, oy + 0.5 * s });
      segs.add(new float[] { ox + (nx - 0.5) * s, oy + (ny - 0.5) * s, ox + (nx - 0.5) * s, oy + ny * s });
    }
  }
  chainSegments(segs, out);
}

// ----- 18: L-system ------
void genLSystem(ArrayList<ArrayList<PVector>> out) {
  int type = (int) pv(0), iters = (int) pv(1), smooth = (int) pv(4);
  float tweak = pv(2), jitter = pv(3);
  String axiom;
  String[] rules;                  // pairs: symbol, replacement
  float ang, heading = 0;
  switch (type) {
    case 0:  axiom = "F--F--F"; rules = new String[] { "F", "F+F--F+F" }; ang = 60; break;
    case 1:  axiom = "FX"; rules = new String[] { "X", "X+YF+", "Y", "-FX-Y" }; ang = 90; break;
    case 2:  axiom = "A"; rules = new String[] { "A", "A-B--B+A++AA+B-", "B", "+A-AA--A-B++B+A" }; ang = 60; break;
    case 3:  axiom = "A"; rules = new String[] { "A", "B-A-B", "B", "A+B+A" }; ang = 60; break;
    default: axiom = "X"; rules = new String[] { "X", "F+[[X]-X]-F[-FX]+X", "F", "FF" }; ang = 25; heading = -90; break;
  }
  StringBuilder str = new StringBuilder(axiom);
  for (int it = 0; it < iters; it++) {                 // stops early once the string gets huge
    StringBuilder nx = new StringBuilder(str.length() * 4);
    for (int i = 0; i < str.length(); i++) {
      char ch = str.charAt(i);
      String rep = null;
      for (int r = 0; r < rules.length; r += 2) if (rules[r].charAt(0) == ch) rep = rules[r + 1];
      if (rep != null) nx.append(rep); else nx.append(ch);
    }
    if (nx.length() > 300000) break;
    str = nx;
  }

  float a = radians(ang + tweak), hd = radians(heading), x = 0, y = 0;
  ArrayList<ArrayList<PVector>> raw = new ArrayList<ArrayList<PVector>>();
  ArrayList<float[]> stack = new ArrayList<float[]>();
  ArrayList<PVector> cur = new ArrayList<PVector>();
  cur.add(new PVector(0, 0));
  for (int i = 0; i < str.length(); i++) {
    char ch = str.charAt(i);
    if (ch == 'F' || ch == 'A' || ch == 'B') {
      x += cos(hd); y += sin(hd);
      cur.add(new PVector(x, y));
    } else if (ch == '+' || ch == '-') {
      float t = a * (jitter > 0 ? 1 + random(-jitter, jitter) : 1);
      hd += ch == '+' ? t : -t;
    } else if (ch == '[') {
      stack.add(new float[] { x, y, hd });
    } else if (ch == ']' && !stack.isEmpty()) {
      float[] st = stack.remove(stack.size() - 1);
      if (cur.size() >= 2) raw.add(cur);
      x = st[0]; y = st[1]; hd = st[2];
      cur = new ArrayList<PVector>();
      cur.add(new PVector(x, y));
    }
  }
  if (cur.size() >= 2) raw.add(cur);
  if (smooth > 0) for (int i = 0; i < raw.size(); i++) raw.set(i, chaikin(raw.get(i), smooth));
  fitPaths(raw, out);
}

// ----- 19: guilloche (banknote rosette) ------
void genGuilloche(ArrayList<ArrayList<PVector>> out) {
  int lines = (int) pv(0), osc = (int) pv(1), lobesO = (int) pv(4), lobesI = (int) pv(5), res = (int) pv(7);
  float rOut = pv(2), rIn = min(pv(3), pv(2)), depth = pv(6);
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float R = min(xmax - xmin, ymax - ymin) / 2;
  for (int k = 0; k < lines; k++) {
    float ph = TWO_PI * k / lines;
    ArrayList<PVector> pts = new ArrayList<PVector>(res + 1);
    for (int i = 0; i <= res; i++) {
      float t = TWO_PI * (i % res) / res;
      float ro = R * rOut * (1 - depth * (0.5 - 0.5 * cos(lobesO * t)));
      float ri = R * rIn * (1 - depth * (0.5 + 0.5 * cos(lobesI * t)));
      float r = lerp(ri, ro, 0.5 + 0.5 * sin(osc * t + ph));
      pts.add(new PVector(cx + cos(t) * r, cy + sin(t) * r));
    }
    emit(out, pts);
  }
}

// ----- 20: Maurer rose ------
void genMaurer(ArrayList<ArrayList<PVector>> out) {
  int n = (int) pv(0), d = (int) pv(1), np = (int) pv(2), copies = (int) pv(3), dStep = (int) pv(4);
  boolean rose = pv(5) > 0.5;
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float R = min(xmax - xmin, ymax - ymin) / 2;
  for (int c = 0; c < copies; c++) {
    int dd = d + c * dStep;
    ArrayList<PVector> pts = new ArrayList<PVector>(np + 1);
    for (int k = 0; k <= np; k++) {
      float th = radians((k * (long) dd) % 360);
      float r = R * sin(n * th);
      pts.add(new PVector(cx + cos(th) * r, cy + sin(th) * r));
    }
    emit(out, pts);
  }
  if (rose) {
    int res = 2400;
    ArrayList<PVector> pts = new ArrayList<PVector>(res + 1);
    for (int i = 0; i <= res; i++) {
      float th = TWO_PI * i / res, r = R * sin(n * th);
      pts.add(new PVector(cx + cos(th) * r, cy + sin(th) * r));
    }
    emit(out, pts);
  }
}

// ----- 21: phyllotaxis (sunflower seed pattern) ------
void genPhyllotaxis(ArrayList<ArrayList<PVector>> out) {
  int n = (int) pv(0), mark = (int) pv(2), rings = (int) pv(5), fam = (int) pv(6);
  float golden = radians(137.50776 + pv(1)), size = pv(3), growth = pv(4);
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float R = max(1, min(xmax - xmin, ymax - ymin) / 2 - (mark == 2 ? 0 : size / 2));
  float c = R / sqrt(n);
  PVector[] p = new PVector[n];
  for (int i = 0; i < n; i++) {
    float r = c * sqrt(i + 0.5), a = i * golden;
    p[i] = new PVector(cx + cos(a) * r, cy + sin(a) * r);
  }
  if (mark == 2) {                                     // parastichies: two Fibonacci spiral families
    int[] fib = { 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144 };
    for (int f = fam; f <= fam + 1; f++) {
      int step = fib[f];
      for (int s = 0; s < step && s < n; s++) {
        ArrayList<PVector> pts = new ArrayList<PVector>();
        for (int i = s; i < n; i += step) pts.add(p[i]);
        if (pts.size() >= 2) emit(out, pts);
      }
    }
    return;
  }
  for (int i = 0; i < n; i++) {
    float t = (i + 0.5) / n;
    float d = size * lerp(1, 0.15 + 0.85 * sqrt(t), growth);
    if (mark == 0) {
      for (int k = 1; k <= rings; k++) {
        float r = d / 2 * k / rings;
        if (r < 0.1) continue;
        emit(out, circlePath(p[i].x, p[i].y, r, constrain((int) (r * 10), 10, 60)));
      }
    } else {
      float a = atan2(p[i].y - cy, p[i].x - cx);
      for (int k = 0; k < rings; k++) {                // several short parallel dashes per seed
        float off = (k - (rings - 1) / 2.0) * d * 0.25;
        float ox = -sin(a) * off, oy = cos(a) * off;
        ArrayList<PVector> l = new ArrayList<PVector>();
        l.add(new PVector(p[i].x - cos(a) * d / 2 + ox, p[i].y - sin(a) * d / 2 + oy));
        l.add(new PVector(p[i].x + cos(a) * d / 2 + ox, p[i].y + sin(a) * d / 2 + oy));
        emit(out, l);
      }
    }
  }
}

// ----- 22: recursive subdivision with hatched cells ------
void genSubdivision(ArrayList<ArrayList<PVector>> out) {
  int depth = (int) pv(0);
  float minS = pv(1), var = pv(2), stop = pv(3), fill = pv(4), sp = pv(5), gap = pv(6);
  ArrayList<float[]> leaves = new ArrayList<float[]>(), cuts = new ArrayList<float[]>();
  subdivide(xmin, ymin, xmax, ymax, 0, depth, minS, var, stop, leaves, cuts);

  if (gap <= 0) {
    emit(out, rectPath(xmin, ymin, xmax, ymax));
    for (float[] c : cuts) {
      ArrayList<PVector> l = new ArrayList<PVector>();
      l.add(new PVector(c[0], c[1])); l.add(new PVector(c[2], c[3]));
      emit(out, l);
    }
  }
  float g = gap / 2;
  for (float[] r : leaves) {
    float x0 = r[0] + g, y0 = r[1] + g, x1 = r[2] - g, y1 = r[3] - g;
    boolean filled = random(1) < fill;
    int style = (int) random(6);
    if (x1 - x0 < 0.3 || y1 - y0 < 0.3) continue;
    if (gap > 0) emit(out, rectPath(x0, y0, x1, y1));
    if (!filled) continue;
    switch (style) {
      case 0: hatchRect(out, x0, y0, x1, y1, 0, sp); break;
      case 1: hatchRect(out, x0, y0, x1, y1, HALF_PI, sp); break;
      case 2: hatchRect(out, x0, y0, x1, y1, QUARTER_PI, sp); break;
      case 3: hatchRect(out, x0, y0, x1, y1, -QUARTER_PI, sp); break;
      case 4: hatchRect(out, x0, y0, x1, y1, 0, sp); hatchRect(out, x0, y0, x1, y1, HALF_PI, sp); break;
      default:
        for (float k = sp; x1 - x0 > 2 * k + 0.3 && y1 - y0 > 2 * k + 0.3; k += sp) emit(out, rectPath(x0 + k, y0 + k, x1 - k, y1 - k));
    }
  }
}

void subdivide(float x0, float y0, float x1, float y1, int lvl, int depth, float minS, float var, float stop,
               ArrayList<float[]> leaves, ArrayList<float[]> cuts) {
  float w = x1 - x0, h = y1 - y0;
  boolean canX = w >= 2 * minS, canY = h >= 2 * minS;
  if (lvl >= depth || (!canX && !canY) || (lvl >= 2 && random(1) < stop)) {
    leaves.add(new float[] { x0, y0, x1, y1 });
    return;
  }
  boolean vert = canX && (!canY || random(1) < w / (w + h));
  float t = 0.5 + random(-var, var);
  if (vert) {
    float x = constrain(x0 + w * t, x0 + minS, x1 - minS);
    cuts.add(new float[] { x, y0, x, y1 });
    subdivide(x0, y0, x, y1, lvl + 1, depth, minS, var, stop, leaves, cuts);
    subdivide(x, y0, x1, y1, lvl + 1, depth, minS, var, stop, leaves, cuts);
  } else {
    float y = constrain(y0 + h * t, y0 + minS, y1 - minS);
    cuts.add(new float[] { x0, y, x1, y });
    subdivide(x0, y0, x1, y, lvl + 1, depth, minS, var, stop, leaves, cuts);
    subdivide(x0, y, x1, y1, lvl + 1, depth, minS, var, stop, leaves, cuts);
  }
}

// ----- 23: warped grid (op-art lens bulges) ------
void genWarpedGrid(ArrayList<ArrayList<PVector>> out) {
  int lines = (int) pv(0), dir = (int) pv(1), nb = (int) pv(2), res = (int) pv(6);
  float strength = pv(3), rad = pv(4), warp = pv(5);
  noiseDetail(2, 0.5);
  float w = xmax - xmin, h = ymax - ymin;
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float r = rad * min(w, h), sp = min(w, h) / lines;
  float[] bx = new float[nb], by = new float[nb];
  for (int b = 0; b < nb; b++) {
    if (nb == 1) { bx[b] = cx; by[b] = cy; }
    else { bx[b] = xmin + w * random(0.15, 0.85); by[b] = ymin + h * random(0.15, 0.85); }
  }
  int nh = floor(h / sp), nv = floor(w / sp);
  float oy = cy - nh * sp / 2, ox = cx - nv * sp / 2;
  for (int pass = 0; pass < 2; pass++) {
    if (pass == 0 && dir == 1) continue;
    if (pass == 1 && dir == 0) continue;
    int count = pass == 0 ? nh : nv;
    for (int k = 0; k <= count; k++) {
      ArrayList<PVector> pts = new ArrayList<PVector>(res + 1);
      for (int i = 0; i <= res; i++) {
        float u = i / (float) res;
        float x = pass == 0 ? xmin + w * u : ox + k * sp;
        float y = pass == 0 ? oy + k * sp : ymin + h * u;
        float dx = 0, dy = 0;
        for (int b = 0; b < nb; b++) {
          float ex = x - bx[b], ey = y - by[b];
          float f = strength * exp(-(ex * ex + ey * ey) / (r * r));
          dx += ex * f; dy += ey * f;
        }
        if (warp > 0) {
          dx += (noise(x * 0.02, y * 0.02, 3.3) - 0.5) * 2 * warp;
          dy += (noise(x * 0.02, y * 0.02, 7.7) - 0.5) * 2 * warp;
        }
        pts.add(new PVector(x + dx, y + dy));
      }
      emit(out, pts);
    }
  }
}

// ----- 24: fractal tree ------
int tCount, tBranches;
float tAng, tAngVar, tRatio, tLenVar, tBend;

void genTree(ArrayList<ArrayList<PVector>> out) {
  int depth = (int) pv(0);
  tBranches = (int) pv(1); tAng = radians(pv(2)); tAngVar = pv(3);
  tRatio = pv(4); tLenVar = pv(5); tBend = radians(pv(6));
  tCount = 0;
  ArrayList<ArrayList<PVector>> raw = new ArrayList<ArrayList<PVector>>();
  ArrayList<PVector> trunk = new ArrayList<PVector>();
  trunk.add(new PVector(0, 0));
  raw.add(trunk);
  treeGrow(raw, trunk, 0, 0, -HALF_PI, 1, depth);
  fitPaths(raw, out);
}

// The first child continues the parent's stroke, so each branch tip ends a pen-down run.
void treeGrow(ArrayList<ArrayList<PVector>> raw, ArrayList<PVector> path, float x, float y, float a, float len, int d) {
  if (d <= 0 || tCount > 200000) return;
  int sub = 4;
  for (int s = 0; s < sub; s++) {
    a += tBend / sub;
    x += cos(a) * len / sub; y += sin(a) * len / sub;
    path.add(new PVector(x, y));
  }
  tCount += sub;
  for (int b = 0; b < tBranches; b++) {
    float spread = lerp(-tAng, tAng, b / (float) (tBranches - 1));
    float na = a + spread + random(-1, 1) * tAng * tAngVar;
    float nl = len * tRatio * (1 + random(-1, 1) * tLenVar);
    ArrayList<PVector> p = path;
    if (b > 0) { p = new ArrayList<PVector>(); p.add(new PVector(x, y)); raw.add(p); }
    treeGrow(raw, p, x, y, na, nl, d - 1);
  }
}

// ----- 25: Voronoi cells (with Lloyd relaxation and inset rings) ------
void genVoronoi(ArrayList<ArrayList<PVector>> out) {
  int n = (int) pv(0), relax = (int) pv(1), rings = (int) pv(3), smooth = (int) pv(5);
  float bias = pv(2), gap = pv(4);
  boolean borders = pv(6) > 0.5;
  float w = xmax - xmin, h = ymax - ymin;
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float[] px = new float[n], py = new float[n];
  for (int i = 0; i < n; i++) {
    float k = 1 - bias * random(1);
    px[i] = cx + (random(xmin, xmax) - cx) * k;
    py[i] = cy + (random(ymin, ymax) - cy) * k;
  }
  long[] keys = new long[n];
  for (int it = 0; it < relax; it++) {                // Lloyd: move each site to its cell's centroid
    float[] nx = new float[n], ny = new float[n];
    for (int i = 0; i < n; i++) {
      ArrayList<PVector> cell = vorCell(px, py, n, i, sortByDist(px, py, n, i, keys), 0);
      PVector c = polyCentroid(cell);
      nx[i] = c == null ? px[i] : c.x; ny[i] = c == null ? py[i] : c.y;
    }
    px = nx; py = ny;
  }
  ArrayList<float[]> segs = new ArrayList<float[]>();
  for (int i = 0; i < n; i++) {
    sortByDist(px, py, n, i, keys);
    if (borders) {
      ArrayList<PVector> cell = vorCell(px, py, n, i, keys, 0);
      for (int k = 0; k < cell.size(); k++) {
        PVector a = cell.get(k), b = cell.get((k + 1) % cell.size());
        segs.add(new float[] { a.x, a.y, b.x, b.y });
      }
    }
    for (int r = 1; r <= rings; r++) {
      ArrayList<PVector> cell = vorCell(px, py, n, i, keys, r * gap);
      if (cell.size() < 3) break;
      emit(out, chaikinClosed(cell, smooth));
    }
  }
  chainSegments(segs, out);
}

long[] sortByDist(float[] px, float[] py, int n, int i, long[] keys) {
  for (int j = 0; j < n; j++) {
    float d2 = j == i ? Float.MAX_VALUE : sq(px[j] - px[i]) + sq(py[j] - py[i]);
    keys[j] = ((long) Float.floatToIntBits(d2) << 32) | j;    // non-negative floats sort like their bits
  }
  Arrays.sort(keys);
  return keys;
}

// Cell of site i, shrunk inwards by 'inset' mm, built by clipping the drawing
// area with the bisector half-planes of the nearest sites first.
ArrayList<PVector> vorCell(float[] px, float[] py, int n, int i, long[] keys, float inset) {
  ArrayList<PVector> poly = new ArrayList<PVector>();
  if (xmax - xmin <= 2 * inset || ymax - ymin <= 2 * inset) return poly;
  poly.add(new PVector(xmin + inset, ymin + inset)); poly.add(new PVector(xmax - inset, ymin + inset));
  poly.add(new PVector(xmax - inset, ymax - inset)); poly.add(new PVector(xmin + inset, ymax - inset));
  float maxR = polyReach(poly, px[i], py[i]);
  for (int k = 0; k < n - 1; k++) {
    int j = (int) (keys[k] & 0xffffffffL);
    float dx = px[j] - px[i], dy = py[j] - py[i], dd = sqrt(dx * dx + dy * dy);
    if (dd < 1e-6) continue;
    if (dd / 2 - inset > maxR) break;                  // this and all farther bisectors miss the cell
    float ux = dx / dd, uy = dy / dd;
    poly = clipHalf(poly, ux, uy, ux * (px[i] + dx / 2) + uy * (py[i] + dy / 2) - inset);
    if (poly.size() < 3) return new ArrayList<PVector>();
    maxR = polyReach(poly, px[i], py[i]);
  }
  return poly;
}

float polyReach(ArrayList<PVector> poly, float x, float y) {
  float m = 0;
  for (PVector v : poly) m = max(m, dist(v.x, v.y, x, y));
  return m;
}

// Keep the part of a convex polygon where nx*x + ny*y <= c.
ArrayList<PVector> clipHalf(ArrayList<PVector> poly, float nx, float ny, float c) {
  ArrayList<PVector> res = new ArrayList<PVector>(poly.size() + 1);
  int n = poly.size();
  for (int i = 0; i < n; i++) {
    PVector a = poly.get(i), b = poly.get((i + 1) % n);
    float da = nx * a.x + ny * a.y - c, db = nx * b.x + ny * b.y - c;
    if (da <= 0) res.add(a);
    if ((da <= 0) != (db <= 0)) {
      float t = da / (da - db);
      res.add(new PVector(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
    }
  }
  return res;
}

PVector polyCentroid(ArrayList<PVector> poly) {
  float A = 0, sx = 0, sy = 0;
  for (int i = 0; i < poly.size(); i++) {
    PVector a = poly.get(i), b = poly.get((i + 1) % poly.size());
    float cr = a.x * b.y - b.x * a.y;
    A += cr; sx += (a.x + b.x) * cr; sy += (a.y + b.y) * cr;
  }
  if (abs(A) < 1e-9) return null;
  return new PVector(sx / (3 * A), sy / (3 * A));
}

// ----- 26: image (photo) ------
void photoSelected(File f) { if (f != null) pendingPhoto = f; }

void loadPhoto(File f) {
  PImage img = null;
  try { img = loadImage(f.getAbsolutePath()); } catch (Exception e) { img = null; }
  if (img == null || img.width <= 0) { setStatus("Could not read " + f.getName()); return; }
  setPhoto(img);
  photoPath = f.getAbsolutePath();
  setStatus("Image loaded: " + f.getName());
  photoChanged();
}

// Keep a grey-scale copy (max 1000 px) of the photo; transparent pixels count as white.
void setPhoto(PImage img) {
  img = img.copy();
  if (max(img.width, img.height) > 1000) { if (img.width >= img.height) img.resize(1000, 0); else img.resize(0, 1000); }
  img.loadPixels();
  photo = img; photoW = img.width; photoH = img.height;
  photoLum = new float[photoW * photoH];
  for (int i = 0; i < photoLum.length; i++) {
    int c = img.pixels[i];
    float a = ((c >>> 24) & 255) / 255.0;
    float l = (0.299 * ((c >> 16) & 255) + 0.587 * ((c >> 8) & 255) + 0.114 * (c & 255)) / 255.0;
    photoLum[i] = 1 - a * (1 - l);
  }
}

void photoChanged() {
  photoVersion++;
  for (Layer L : layers) if (L.pMode.i() == 26) L.dirty = true;
}

float imgContrast = 1, imgBright = 0;
boolean imgInvert = false;

// Darkness 0 (white) .. 1 (black) of the picture at page position x, y (mm).
float darkAt(float x, float y) {
  float u = (x - imgX) / imgW, v = (y - imgY) / imgH;
  if (u < 0 || v < 0 || u >= 1 || v >= 1) return 0;
  float d;
  if (photoLum == null) d = demoDark(u, v, imgW / imgH);
  else d = 1 - photoLum[min(photoH - 1, (int) (v * photoH)) * photoW + min(photoW - 1, (int) (u * photoW))];
  d = constrain((d - 0.5) * imgContrast + 0.5 - imgBright, 0, 1);
  return imgInvert ? 1 - d : d;
}

// Built-in demo picture: a lit sphere with a soft shadow on a light floor.
float demoDark(float u, float v, float aspect) {
  float X = (u - 0.5) * aspect, Y = v - 0.5, R = 0.3 * min(1, aspect);
  float sx = X / R, sy = (Y + 0.05) / R, rr = sx * sx + sy * sy;
  if (rr < 1) {
    float sz = sqrt(1 - rr);
    float lit = max(0, -0.45 * sx - 0.55 * sy + 0.7 * sz);
    return 0.92 - 0.85 * lit;
  }
  float sh = sq(X / (R * 1.3)) + sq((Y - R * 0.95) / (R * 0.25));
  float d = 0.02 + 0.1 * v;
  if (sh < 1) d += 0.55 * (1 - sh);
  return d;
}

void genImage(ArrayList<ArrayList<PVector>> out) {
  int style = (int) pv(0), npts = (int) pv(1), lines = (int) pv(2);
  imgContrast = pv(3); imgBright = pv(4);
  float ang = radians(pv(5)), amp = pv(6), freq = pv(7), dot = pv(8);
  imgInvert = pv(9) > 0.5;
  float aw = xmax - xmin, ah = ymax - ymin;
  if (photoLum == null) { imgX = xmin; imgY = ymin; imgW = aw; imgH = ah; }
  else {
    float sc = min(aw / photoW, ah / photoH);
    imgW = photoW * sc; imgH = photoH * sc; imgX = xmin + (aw - imgW) / 2; imgY = ymin + (ah - imgH) / 2;
  }
  // clip everything to the picture while generating
  float sx0 = xmin, sy0 = ymin, sx1 = xmax, sy1 = ymax;
  xmin = imgX; ymin = imgY; xmax = imgX + imgW; ymax = imgY + imgH;
  try {
    if (style <= 1) imageStipple(out, npts, style == 0, dot);
    else if (style == 2) imageHatch(out, lines, ang);
    else if (style == 3) imageSpiral(out, lines, amp, freq);
    else imageSquiggle(out, lines, ang, amp, freq);
  } finally {
    xmin = sx0; ymin = sy0; xmax = sx1; ymax = sy1;
  }
}

// Stratified random points, kept with a probability equal to the darkness.
// As a TSP line they are joined into one stroke (nearest neighbour + 2-opt).
void imageStipple(ArrayList<ArrayList<PVector>> out, int n, boolean tour, float dot) {
  float aw = xmax - xmin, ah = ymax - ymin, mean = 0;
  for (int i = 0; i < 2000; i++) mean += darkAt(random(xmin, xmax), random(ymin, ymax)) / 2000;
  float cells = min(n / max(mean, 0.01), n * 100.0);
  float c = sqrt(aw * ah / cells);
  ArrayList<ArrayList<PVector>> pts = new ArrayList<ArrayList<PVector>>();
  for (float y = ymin; y < ymax; y += c) {
    for (float x = xmin; x < xmax; x += c) {
      float px = x + random(c), py = y + random(c);
      if (px > xmax || py > ymax || random(1) >= darkAt(px, py)) continue;
      if (tour) { ArrayList<PVector> one = new ArrayList<PVector>(); one.add(new PVector(px, py)); pts.add(one); }
      else out.add(circlePath(px, py, dot / 2, max(6, round(dot * 10))));
    }
  }
  if (!tour || pts.size() < 2) return;
  ArrayList<PVector> path = orderPaths(pts, true, Float.MAX_VALUE).get(0);
  twoOpt(path, 250);
  out.add(path);
}

// 2-opt improvement of an open tour, within a time budget.
void twoOpt(ArrayList<PVector> p, int budgetMs) {
  int n = p.size();
  if (n < 4) return;
  float[] xs = new float[n], ys = new float[n];
  for (int i = 0; i < n; i++) { xs[i] = p.get(i).x; ys[i] = p.get(i).y; }
  int t0 = millis();
  boolean improved = true;
  while (improved && millis() - t0 < budgetMs) {
    improved = false;
    for (int i = 0; i < n - 3; i++) {
      if ((i & 63) == 0 && millis() - t0 >= budgetMs) break;
      float ax = xs[i], ay = ys[i], bx = xs[i + 1], by = ys[i + 1];
      float dab = dist(ax, ay, bx, by);
      for (int j = i + 2; j < n - 1; j++) {
        float cx = xs[j], cy = ys[j], dx = xs[j + 1], dy = ys[j + 1];
        float dac = dist(ax, ay, cx, cy);
        if (dac >= dab + dab) continue;                  // heuristic: skip far-away candidates
        float delta = dac + dist(bx, by, dx, dy) - dab - dist(cx, cy, dx, dy);
        if (delta < -1e-4) {
          for (int lo = i + 1, hi = j; lo < hi; lo++, hi--) {
            float tx = xs[lo]; xs[lo] = xs[hi]; xs[hi] = tx;
            float ty = ys[lo]; ys[lo] = ys[hi]; ys[hi] = ty;
          }
          bx = xs[i + 1]; by = ys[i + 1];
          dab = dist(ax, ay, bx, by);
          improved = true;
        }
      }
    }
  }
  for (int i = 0; i < n; i++) p.set(i, new PVector(xs[i], ys[i]));
}

// Up to four hatch directions; each one only where the picture is dark enough.
void imageHatch(ArrayList<ArrayList<PVector>> out, int lines, float ang) {
  float sp = (ymax - ymin) / lines;
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2, R = 0.5 * dist(xmin, ymin, xmax, ymax) + 1;
  float[] thr = { 0.15, 0.38, 0.6, 0.8 };
  float[] rot = { 0, HALF_PI, QUARTER_PI, -QUARTER_PI };
  for (int k = 0; k < 4; k++) {
    float a = ang + rot[k], ux = cos(a), uy = sin(a), nx = -uy, ny = ux;
    for (float off = -R + sp / 2; off <= R; off += sp) {
      PVector runStart = null, runEnd = null;
      for (float t = -R; t <= R + 0.4; t += 0.4) {
        float x = cx + ux * t + nx * off, y = cy + uy * t + ny * off;
        boolean ok = x >= xmin && x <= xmax && y >= ymin && y <= ymax && darkAt(x, y) > thr[k];
        if (ok) {
          if (runStart == null) runStart = new PVector(x, y);
          runEnd = new PVector(x, y);
        }
        if ((!ok || t > R) && runStart != null) {
          if (PVector.dist(runStart, runEnd) > 0.5) { ArrayList<PVector> l = new ArrayList<PVector>(); l.add(runStart); l.add(runEnd); out.add(l); }
          runStart = null;
        }
      }
    }
  }
}

// One Archimedean spiral; the wiggle amplitude follows the darkness.
void imageSpiral(ArrayList<ArrayList<PVector>> out, int turns, float amp, float freq) {
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2, R = 0.5 * dist(xmin, ymin, xmax, ymax);
  float sp = R / turns, ds = constrain(1 / (freq * 8), 0.08, 0.3);
  ArrayList<PVector> pts = new ArrayList<PVector>();
  float theta = 0, phase = 0;
  while (true) {
    float r = sp * theta / TWO_PI;
    if (r > R) break;
    float c = cos(theta), s = sin(theta);
    float off = amp * sp * 0.5 * darkAt(cx + c * r, cy + s * r) * sin(phase);
    pts.add(new PVector(cx + c * (r + off), cy + s * (r + off)));
    theta += ds / max(r, sp * 0.5);
    phase += ds * TWO_PI * freq;
  }
  emit(out, pts);
}

// Parallel lines with a sine wiggle whose amplitude follows the darkness.
void imageSquiggle(ArrayList<ArrayList<PVector>> out, int lines, float ang, float amp, float freq) {
  float sp = (ymax - ymin) / lines, ds = constrain(1 / (freq * 8), 0.08, 0.3);
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2, R = 0.5 * dist(xmin, ymin, xmax, ymax) + 1;
  float ux = cos(ang), uy = sin(ang), nx = -uy, ny = ux;
  for (float off = -R + sp / 2; off <= R; off += sp) {
    ArrayList<PVector> pts = new ArrayList<PVector>();
    float phase = 0;
    for (float t = -R; t <= R; t += ds) {
      float x = cx + ux * t + nx * off, y = cy + uy * t + ny * off;
      float o = amp * sp * 0.5 * darkAt(x, y) * sin(phase);
      pts.add(new PVector(x + nx * o, y + ny * o));
      phase += ds * TWO_PI * freq;
    }
    emit(out, pts);
  }
}

// ----- 27: hex Truchet ------
// Pointy-top hexagons. Every tile connects the six edge midpoints in pairs:
// "Arcs" = three arcs around alternate corners, "Mixed" = one straight line
// through the centre plus two arcs. Shared edge points make the strokes
// continue from tile to tile; chainSegments joins them into long lines.
void genHexTruchet(ArrayList<ArrayList<PVector>> out) {
  int n = (int) pv(0), style = (int) pv(1), lines = (int) pv(2);
  float bias = pv(3), spread = pv(4);
  boolean outline = pv(5) > 0.5;
  float w = xmax - xmin, h = ymax - ymin;
  float s = min(w, h) / (n * sqrt(3)), hw = sqrt(3) * s, vh = 1.5 * s;
  int cols = ceil(w / hw) + 2, rows = ceil(h / vh) + 2;
  ArrayList<float[]> segs = new ArrayList<float[]>();
  float[] qx = new float[6], qy = new float[6];
  for (int r = -1; r < rows; r++) {
    for (int c = -1; c < cols; c++) {
      float cx = xmin + c * hw + ((r & 1) == 1 ? hw / 2 : 0), cy = ymin + r * vh;
      for (int k = 0; k < 6; k++) { float a = radians(60 * k + 30); qx[k] = cx + cos(a) * s; qy[k] = cy + sin(a) * s; }
      boolean arcs = style == 0 || (style == 2 && random(1) < bias);
      int rot = (int) random(6);
      for (int li = 0; li < lines; li++) {
        float o = (li - (lines - 1) / 2.0) * spread * s / lines;     // offset from the edge midpoint
        if (arcs) {
          for (int m = 0; m < 3; m++) hexArc(segs, qx, qy, (rot + 2 * m + 1) % 6, cx, cy, s / 2 + o);
        } else {
          int ea = rot % 6, eb = (rot + 3) % 6;
          float ex = (qx[(ea + 1) % 6] - qx[ea]) / s, ey = (qy[(ea + 1) % 6] - qy[ea]) / s;
          float ax = (qx[ea] + qx[(ea + 1) % 6]) / 2 + ex * o, ay = (qy[ea] + qy[(ea + 1) % 6]) / 2 + ey * o;
          float bx = (qx[eb] + qx[(eb + 1) % 6]) / 2 + ex * o, by = (qy[eb] + qy[(eb + 1) % 6]) / 2 + ey * o;
          segs.add(new float[] { ax, ay, bx, by });
          hexArc(segs, qx, qy, (rot + 2) % 6, cx, cy, s / 2 + o);
          hexArc(segs, qx, qy, (rot + 5) % 6, cx, cy, s / 2 - o);
        }
      }
      if (outline) for (int k = 0; k < 6; k++) segs.add(new float[] { qx[k], qy[k], qx[(k + 1) % 6], qy[(k + 1) % 6] });
    }
  }
  chainSegments(segs, out);
}

// 120-degree arc inside the hexagon around corner k, as short segments.
void hexArc(ArrayList<float[]> segs, float[] qx, float[] qy, int k, float cx, float cy, float r) {
  if (r <= 0.05) return;
  float mid = atan2(cy - qy[k], cx - qx[k]);
  int m = max(6, min(24, round(r * 2)));
  float px = qx[k] + cos(mid - PI / 3) * r, py = qy[k] + sin(mid - PI / 3) * r;
  for (int i = 1; i <= m; i++) {
    float a = mid - PI / 3 + TWO_PI / 3 * i / m;
    float x = qx[k] + cos(a) * r, y = qy[k] + sin(a) * r;
    segs.add(new float[] { px, py, x, y });
    px = x; py = y;
  }
}

// ----- 28: Penrose (P3 rhombs) ------
// Robinson triangle subdivision, starting from a wheel of ten triangles.
// Each triangle is {type, ax, ay, bx, by, cx, cy} with apex A; two triangles
// sharing their base B-C form one rhomb, so only A-B and A-C are drawn.
// The arcs are centred on A and pass through the edge midpoints, so they
// always continue into the neighbouring rhomb.
void genPenrose(ArrayList<ArrayList<PVector>> out) {
  int div = (int) pv(0), style = (int) pv(1);
  float zoom = pv(2), rot = radians(pv(3));
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2, R = zoom * 0.5 * dist(xmin, ymin, xmax, ymax);
  float phi = (1 + sqrt(5)) / 2;
  ArrayList<float[]> tris = new ArrayList<float[]>();
  for (int i = 0; i < 10; i++) {
    float ab = (2 * i - 1) * PI / 10 + rot, ac = (2 * i + 1) * PI / 10 + rot;
    float bx = cx + cos(ab) * R, by = cy + sin(ab) * R, ccx = cx + cos(ac) * R, ccy = cy + sin(ac) * R;
    if (i % 2 == 0) tris.add(new float[] { 0, cx, cy, ccx, ccy, bx, by });
    else tris.add(new float[] { 0, cx, cy, bx, by, ccx, ccy });
  }
  for (int d = 0; d < div; d++) {
    ArrayList<float[]> next = new ArrayList<float[]>(tris.size() * 3);
    for (float[] t : tris) {
      if (!triNearArea(t)) continue;
      float ax = t[1], ay = t[2], bx = t[3], by = t[4], tx = t[5], ty = t[6];
      if (t[0] == 0) {
        float px = ax + (bx - ax) / phi, py = ay + (by - ay) / phi;
        next.add(new float[] { 0, tx, ty, px, py, bx, by });
        next.add(new float[] { 1, px, py, tx, ty, ax, ay });
      } else {
        float qx = bx + (ax - bx) / phi, qy = by + (ay - by) / phi;
        float rx = bx + (tx - bx) / phi, ry = by + (ty - by) / phi;
        next.add(new float[] { 1, rx, ry, tx, ty, ax, ay });
        next.add(new float[] { 1, qx, qy, rx, ry, bx, by });
        next.add(new float[] { 0, rx, ry, qx, qy, ax, ay });
      }
    }
    tris = next;
  }
  ArrayList<float[]> segs = new ArrayList<float[]>();
  for (float[] t : tris) {
    if (!triNearArea(t)) continue;
    float ax = t[1], ay = t[2];
    if (style != 1) {
      segs.add(new float[] { t[5], t[6], ax, ay });
      segs.add(new float[] { ax, ay, t[3], t[4] });
    }
    if (style != 0) {
      float r = dist(ax, ay, t[3], t[4]) / 2;
      float a0 = atan2(t[4] - ay, t[3] - ax), a1 = atan2(t[6] - ay, t[5] - ax);
      float da = a1 - a0;
      while (da > PI) da -= TWO_PI;
      while (da < -PI) da += TWO_PI;
      int m = max(4, min(16, round(r * abs(da) / 0.8)));
      float px = ax + cos(a0) * r, py = ay + sin(a0) * r;
      for (int i = 1; i <= m; i++) {
        float a = a0 + da * i / m, x = ax + cos(a) * r, y = ay + sin(a) * r;
        segs.add(new float[] { px, py, x, y });
        px = x; py = y;
      }
    }
  }
  chainSegments(segs, out);
}

boolean triNearArea(float[] t) {
  float x0 = min(t[1], min(t[3], t[5])), x1 = max(t[1], max(t[3], t[5]));
  float y0 = min(t[2], min(t[4], t[6])), y1 = max(t[2], max(t[4], t[6]));
  return x1 >= xmin && x0 <= xmax && y1 >= ymin && y0 <= ymax;
}

// ----- 29: hex maze ------
// Recursive backtracker on a grid of pointy-top hexagons. Edge k of a cell
// runs from corner k to corner k + 1; the neighbour across it is found
// geometrically and faces back with edge k + 3.
void genHexMaze(ArrayList<ArrayList<PVector>> out) {
  int cellsN = (int) pv(0), style = (int) pv(1);
  float loops = pv(2);
  boolean doors = pv(3) > 0.5;
  float w = xmax - xmin, h = ymax - ymin;
  float s = min(w, h) / (cellsN * sqrt(3)), hw = sqrt(3) * s, vh = 1.5 * s;
  int cols = max(1, floor((w - hw / 2) / hw)), rows = max(1, floor((h - 2 * s) / vh) + 1);
  float ox = xmin + (w - (cols * hw + hw / 2)) / 2 + hw / 2, oy = ymin + (h - ((rows - 1) * vh + 2 * s)) / 2 + s;
  int n = cols * rows;
  float[] ccx = new float[n], ccy = new float[n];
  for (int r = 0; r < rows; r++) for (int c = 0; c < cols; c++) {
    ccx[r * cols + c] = ox + c * hw + ((r & 1) == 1 ? hw / 2 : 0);
    ccy[r * cols + c] = oy + r * vh;
  }
  int[] nb = new int[n * 6];
  for (int i = 0; i < n; i++) {
    for (int k = 0; k < 6; k++) {
      float a = radians(60 * k + 60);
      float x = ccx[i] + cos(a) * hw, y = ccy[i] + sin(a) * hw;
      int r = round((y - oy) / vh);
      int c = round((x - ox - ((r & 1) == 1 ? hw / 2 : 0)) / hw);
      nb[i * 6 + k] = (r >= 0 && r < rows && c >= 0 && c < cols) ? r * cols + c : -1;
    }
  }
  boolean[] open = new boolean[n * 6], vis = new boolean[n];
  int[] stack = new int[n], cand = new int[6];
  int sp = 0, start = (int) random(n);
  vis[start] = true; stack[sp++] = start;
  while (sp > 0) {
    int c = stack[sp - 1], nc = 0;
    for (int k = 0; k < 6; k++) { int m = nb[c * 6 + k]; if (m >= 0 && !vis[m]) cand[nc++] = k; }
    if (nc == 0) { sp--; continue; }
    int k = cand[(int) random(nc)], m = nb[c * 6 + k];
    open[c * 6 + k] = true; open[m * 6 + (k + 3) % 6] = true;
    vis[m] = true; stack[sp++] = m;
  }
  if (loops > 0) {
    for (int i = 0; i < n; i++) for (int k = 0; k < 3; k++) {
      int m = nb[i * 6 + k];
      if (m >= 0 && !open[i * 6 + k] && random(1) < loops * 0.3) { open[i * 6 + k] = true; open[m * 6 + k + 3] = true; }
    }
  }
  int door0 = 0, door1 = n - 1;
  if (doors) { open[door0 * 6 + 4] = true; open[door1 * 6 + 1] = true; }   // top edge of the first cell, bottom of the last

  ArrayList<float[]> segs = new ArrayList<float[]>();
  for (int i = 0; i < n; i++) {
    for (int k = 0; k < 6; k++) {
      float a0 = radians(60 * k + 30), a1 = radians(60 * k + 90);
      if (style == 0) {
        if (!open[i * 6 + k]) segs.add(new float[] { ccx[i] + cos(a0) * s, ccy[i] + sin(a0) * s, ccx[i] + cos(a1) * s, ccy[i] + sin(a1) * s });
      } else if (open[i * 6 + k]) {
        int m = nb[i * 6 + k];
        if (m > i) segs.add(new float[] { ccx[i], ccy[i], ccx[m], ccy[m] });
        else if (m < 0) {                                  // door: run out to the edge
          float a = radians(60 * k + 60);
          segs.add(new float[] { ccx[i], ccy[i], ccx[i] + cos(a) * hw / 2, ccy[i] + sin(a) * hw / 2 });
        }
      }
    }
  }
  chainSegments(segs, out);
}

// ---------- export --------------------------------------------------------
String timestamp() {
  return year() + nf(month(), 2) + nf(day(), 2) + "_" + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2);
}

String slug(String s) { return s.toLowerCase().replace(' ', '_'); }

String ext() { return FORMAT_EXT[pFormat.i()]; }

void requestExport() {
  selectOutput("Save " + FORMAT_NAMES[pFormat.i()] + " for plotter", "exportSelected",
    new File(sketchPath("lineart_" + timestamp() + "." + ext())));
}

void exportSelected(File f) {
  if (f == null) return;                       // dialog cancelled
  if (!f.getName().toLowerCase().endsWith("." + ext())) f = new File(f.getAbsolutePath() + "." + ext());
  pendingExport = f;                           // handled on the animation thread
}

void quickSave() {
  File dir = new File(sketchPath("exports"));
  dir.mkdirs();
  pendingExport = new File(dir, "lineart_" + timestamp() + "." + ext());
}

// Locale-independent number formatting (always '.' as decimal separator), 2 decimals.
void appendNum(StringBuilder sb, float v) {
  int n = round(v * 100);
  if (n < 0) { sb.append('-'); n = -n; }
  sb.append(n / 100).append('.');
  int f = n % 100;
  if (f < 10) sb.append('0');
  sb.append(f);
}

// Writes the enabled layers in the chosen format; returns the number of files.
int writeExport(File f) {
  ArrayList<Layer> act = new ArrayList<Layer>();
  for (Layer L : layers) if (L.pEnabled.on() && !L.paths.isEmpty()) act.add(L);
  if (act.isEmpty()) { setStatus("Nothing to export: no visible lines"); return 0; }

  if (pSeparate.on() && act.size() > 1) {
    String base = f.getAbsolutePath(), e = "." + ext();
    if (base.toLowerCase().endsWith(e)) base = base.substring(0, base.length() - e.length());
    for (Layer L : act) {
      ArrayList<Layer> one = new ArrayList<Layer>();
      one.add(L);
      writeFile(new File(base + "_layer" + (L.id + 1) + "_" + slug(PATTERN_NAMES[L.pMode.i()]) + e), one);
    }
    setStatus("Saved " + act.size() + " " + FORMAT_NAMES[pFormat.i()] + " files (one per layer)");
    return act.size();
  }
  writeFile(f, act);
  setStatus("Saved " + f.getName() + " (" + act.size() + (act.size() == 1 ? " layer" : " layers") + ")");
  return 1;
}

void writeFile(File f, ArrayList<Layer> ls) {
  String s;
  if (pFormat.i() == 1) s = gcodeText(ls);
  else if (pFormat.i() == 2) s = hpglText(ls);
  else s = svgText(ls);
  saveStrings(f, new String[] { s });
  println("Saved: " + f.getAbsolutePath());
}

String svgText(ArrayList<Layer> ls) {
  StringBuilder sb = new StringBuilder(1 << 20);
  sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n");
  sb.append("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:inkscape=\"http://www.inkscape.org/namespaces/inkscape\" width=\"");
  appendNum(sb, genW); sb.append("mm\" height=\""); appendNum(sb, genH); sb.append("mm\" viewBox=\"0 0 ");
  appendNum(sb, genW); sb.append(' '); appendNum(sb, genH); sb.append("\">\n");
  for (Layer L : ls) {
    sb.append("<g id=\"layer").append(L.id + 1).append("\" inkscape:groupmode=\"layer\" inkscape:label=\"")
      .append(L.id + 1).append(' ').append(PATTERN_NAMES[L.pMode.i()]).append(' ').append(PEN_NAMES[L.pColor.i()])
      .append("\" fill=\"none\" stroke=\"#").append(hex(L.penColor(), 6)).append("\" stroke-width=\"");
    appendNum(sb, L.pPen.val); sb.append("\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n");
    for (ArrayList<PVector> p : L.paths) {
      sb.append("<path d=\"M");
      for (int i = 0; i < p.size(); i++) {
        if (i > 0) sb.append(" L");
        appendNum(sb, p.get(i).x); sb.append(' '); appendNum(sb, p.get(i).y);
      }
      sb.append("\"/>\n");
    }
    sb.append("</g>\n");
  }
  sb.append("</svg>\n");
  return sb.toString();
}

// G-code for GRBL-style pen plotters: millimetres, absolute coordinates,
// pen lift by Z axis or by servo (M3 S...), G4 dwell after each lift (seconds).
// Several layers in one file are separated by M0 pauses for the pen change.
String gcodeText(ArrayList<Layer> ls) {
  StringBuilder sb = new StringBuilder(1 << 20);
  boolean flip = pFlipY.on(), servo = pLift.i() == 1;
  int fDown = max(1, round(pSpeedDown.val * 60)), fUp = max(1, round(pSpeedUp.val * 60));
  String up = servo ? "M3 S" + pServoUp.i() : "G0 Z" + fmt3(pZUp.val);
  String down = servo ? "M3 S" + pServoDown.i() : "G1 Z" + fmt3(pZDown.val) + " F" + fUp;
  String dwell = pLiftTime.val > 0 ? "G4 P" + fmt3(pLiftTime.val) + "\n" : "";
  sb.append("; Generative Line Art\n; paper ").append(fmt3(genW)).append(" x ").append(fmt3(genH))
    .append(" mm, origin ").append(flip ? "bottom-left (Y up)" : "top-left (Y down)").append('\n');
  sb.append("G21 ; millimetres\nG90 ; absolute\n").append(up).append('\n').append(dwell);
  for (int li = 0; li < ls.size(); li++) {
    Layer L = ls.get(li);
    sb.append("; layer ").append(L.id + 1).append(": ").append(PATTERN_NAMES[L.pMode.i()])
      .append(", pen ").append(PEN_NAMES[L.pColor.i()]).append('\n');
    if (li > 0) sb.append("G1 X0 Y0 F").append(fUp).append("\nM0 ; change to the ").append(PEN_NAMES[L.pColor.i()]).append(" pen, then resume\n");
    for (ArrayList<PVector> p : L.paths) {
      for (int i = 0; i < p.size(); i++) {
        PVector v = p.get(i);
        sb.append("G1 X").append(fmt3(v.x)).append(" Y").append(fmt3(flip ? genH - v.y : v.y));
        if (i == 0) sb.append(" F").append(fUp).append('\n').append(down).append('\n').append(dwell).append("G1 F").append(fDown);
        sb.append('\n');
      }
      sb.append(up).append('\n').append(dwell);
    }
  }
  sb.append("G1 X0 Y0 F").append(fUp).append("\nM2\n");
  return sb.toString();
}

// HPGL: 40 plotter units per mm, origin bottom-left; layer n uses pen n.
String hpglText(ArrayList<Layer> ls) {
  StringBuilder sb = new StringBuilder(1 << 20);
  sb.append("IN;\nVS").append(max(1, round(pSpeedDown.val / 10))).append(";\n");
  for (Layer L : ls) {
    sb.append("SP").append(L.id + 1).append(";\n");
    for (ArrayList<PVector> p : L.paths) {
      sb.append("PU").append(round(p.get(0).x * 40)).append(',').append(round((genH - p.get(0).y) * 40)).append(";\n");
      for (int i = 1; i < p.size(); i += 64) {             // keep commands short for small plotter buffers
        sb.append("PD");
        for (int j = i; j < min(p.size(), i + 64); j++) {
          if (j > i) sb.append(',');
          sb.append(round(p.get(j).x * 40)).append(',').append(round((genH - p.get(j).y) * 40));
        }
        sb.append(";\n");
      }
    }
    sb.append("PU;\n");
  }
  sb.append("PU0,0;\nSP0;\n");
  return sb.toString();
}

String fmt3(float v) { return String.format(Locale.US, "%.3f", v); }

// Exports 'Batch count' variations: every enabled layer's seed is stepped by
// one per design (locked seeds stay), then the original seeds are restored.
void batchExport() {
  int n = pBatch.i();
  File dir = new File(sketchPath("exports/batch_" + timestamp()));
  dir.mkdirs();
  int[] orig = new int[NUM_LAYERS];
  for (Layer L : layers) orig[L.id] = L.pSeed.i();
  int files = 0;
  for (int b = 0; b < n; b++) {
    String tag = "";
    for (Layer L : layers) {
      if (!L.pEnabled.on()) continue;
      if (!L.pSeed.locked) L.pSeed.set((orig[L.id] + b) % 10000);
      tag += "_s" + L.pSeed.i();
    }
    regenerate();
    files += writeExport(new File(dir, "lineart_" + nf(b + 1, 2) + tag + "." + ext()));
  }
  for (Layer L : layers) L.pSeed.set(orig[L.id]);
  regenerate();
  setStatus("Batch: " + n + " designs (" + files + " files) in exports/" + dir.getName());
}

// ---------- presets -------------------------------------------------------
void requestPresetSave() {
  File dir = new File(sketchPath("presets"));
  dir.mkdirs();
  selectOutput("Save preset", "presetSaveSelected", new File(dir, "preset_" + timestamp() + ".json"));
}

void requestPresetLoad() {
  File dir = new File(sketchPath("presets"));
  dir.mkdirs();
  selectInput("Load preset", "presetLoadSelected", dir);
}

void quickSavePreset() {
  File dir = new File(sketchPath("presets"));
  dir.mkdirs();
  pendingPresetSave = new File(dir, "preset_" + timestamp() + ".json");
}

void presetSaveSelected(File f) {
  if (f == null) return;
  if (!f.getName().toLowerCase().endsWith(".json")) f = new File(f.getAbsolutePath() + ".json");
  pendingPresetSave = f;
}

void presetLoadSelected(File f) {
  if (f != null) pendingPresetLoad = f;
}

void savePreset(File f) {
  JSONObject root = new JSONObject();
  root.setString("app", "GenerativeLineArt");
  root.setInt("version", 1);
  root.setString("paper", PAPER_NAMES[pPaper.i()]);
  root.setBoolean("landscape", pLandscape.on());
  root.setFloat("margin", pMargin.val);
  root.setBoolean("optimizeTravel", pOptimize.on());
  root.setBoolean("filePerLayer", pSeparate.on());
  JSONObject st = new JSONObject();                  // every page-level setting, by label
  for (Param p : globals) st.setFloat(p.label, p.val);
  root.setJSONObject("settings", st);
  root.setString("maskText", maskText);
  root.setString("maskImage", maskPath);
  root.setString("photo", photoPath);
  JSONArray arr = new JSONArray();
  for (Layer L : layers) {
    JSONObject o = new JSONObject();
    o.setBoolean("enabled", L.pEnabled.on());
    o.setString("penColour", PEN_NAMES[L.pColor.i()]);
    o.setFloat("penWidth", L.pPen.val);
    o.setInt("seed", L.pSeed.i());
    o.setString("pattern", PATTERN_NAMES[L.pMode.i()]);
    o.setFloat("scale", L.pScale.val);
    o.setFloat("rotate", L.pRot.val);
    o.setFloat("offsetX", L.pOffX.val);
    o.setFloat("offsetY", L.pOffY.val);
    o.setString("mask", L.pMask.opts[L.pMask.i()]);
    JSONArray locks = new JSONArray();
    if (L.pSeed.locked) locks.append("seed");
    for (int m = 0; m < PATTERN_NAMES.length; m++) {
      ArrayList<Param> ps = L.modeParams.get(m);
      for (int k = 0; k < ps.size(); k++) if (ps.get(k).locked) locks.append(PATTERN_NAMES[m] + "/" + k);
    }
    o.setJSONArray("locks", locks);
    JSONObject pp = new JSONObject();
    for (int m = 0; m < PATTERN_NAMES.length; m++) {
      JSONArray a = new JSONArray();
      for (Param p : L.modeParams.get(m)) a.append(p.val);
      pp.setJSONArray(PATTERN_NAMES[m], a);
    }
    o.setJSONObject("params", pp);
    arr.append(o);
  }
  root.setJSONArray("layers", arr);
  if (root.save(f, "indent=2")) setStatus("Preset saved: " + f.getName());
  else setStatus("Could not save preset");
}

int indexOf(String[] arr, String s) {
  for (int i = 0; i < arr.length; i++) if (arr[i].equals(s)) return i;
  return -1;
}

void loadPreset(File f) {
  try {
    JSONObject root = loadJSONObject(f);
    if (root == null || !root.hasKey("layers")) { setStatus("Not a valid preset file"); return; }
    int pi = indexOf(PAPER_NAMES, root.getString("paper", ""));
    if (pi >= 0) pPaper.set(pi);
    pLandscape.set(root.getBoolean("landscape", false) ? 1 : 0);
    pMargin.set(root.getFloat("margin", pMargin.val));
    pOptimize.set(root.getBoolean("optimizeTravel", true) ? 1 : 0);
    pSeparate.set(root.getBoolean("filePerLayer", false) ? 1 : 0);
    if (root.hasKey("settings")) {
      JSONObject st = root.getJSONObject("settings");
      for (Param p : globals) if (st.hasKey(p.label)) p.set(st.getFloat(p.label));
    }
    String mt = root.getString("maskText", maskText);
    if (!mt.equals(maskText)) { maskText = mt; maskChanged(); }
    String mimg = root.getString("maskImage", "");
    if (!mimg.isEmpty() && !mimg.equals(maskPath) && new File(mimg).exists()) loadMaskImage(new File(mimg));
    String ph = root.getString("photo", "");
    if (!ph.isEmpty() && !ph.equals(photoPath) && new File(ph).exists()) loadPhoto(new File(ph));
    JSONArray arr = root.getJSONArray("layers");
    for (int i = 0; i < NUM_LAYERS; i++) {
      Layer L = layers[i];
      if (i >= arr.size()) { L.pEnabled.set(0); continue; }
      JSONObject o = arr.getJSONObject(i);
      L.pEnabled.set(o.getBoolean("enabled", false) ? 1 : 0);
      int ci = indexOf(PEN_NAMES, o.getString("penColour", ""));
      if (ci >= 0) L.pColor.set(ci);
      L.pPen.set(o.getFloat("penWidth", 0.4));
      L.pSeed.set(o.getInt("seed", 1));
      int mi = indexOf(PATTERN_NAMES, o.getString("pattern", ""));
      if (mi >= 0) L.pMode.set(mi);
      L.pScale.set(o.getFloat("scale", 1));
      L.pRot.set(o.getFloat("rotate", 0));
      L.pOffX.set(o.getFloat("offsetX", 0));
      L.pOffY.set(o.getFloat("offsetY", 0));
      L.pMask.set(max(0, indexOf(L.pMask.opts, o.getString("mask", "Off"))));
      HashSet<String> locks = new HashSet<String>();
      if (o.hasKey("locks")) { JSONArray la = o.getJSONArray("locks"); for (int k = 0; k < la.size(); k++) locks.add(la.getString(k)); }
      L.pSeed.locked = locks.contains("seed");
      for (int m = 0; m < PATTERN_NAMES.length; m++) {
        ArrayList<Param> ps = L.modeParams.get(m);
        for (int k = 0; k < ps.size(); k++) ps.get(k).locked = locks.contains(PATTERN_NAMES[m] + "/" + k);
      }
      if (o.hasKey("params")) {
        JSONObject pp = o.getJSONObject("params");
        for (int m = 0; m < PATTERN_NAMES.length; m++) {
          if (!pp.hasKey(PATTERN_NAMES[m])) continue;
          JSONArray a = pp.getJSONArray(PATTERN_NAMES[m]);
          ArrayList<Param> ps = L.modeParams.get(m);
          for (int k = 0; k < ps.size() && k < a.size(); k++) ps.get(k).set(a.getFloat(k));
        }
      }
      L.dirty = true;
    }
    curLayer = 0;
    previewStale = true;
    setStatus("Preset loaded: " + f.getName());
  } catch (Exception e) {
    println("Preset error: " + e);
    setStatus("Could not read preset");
  }
}
