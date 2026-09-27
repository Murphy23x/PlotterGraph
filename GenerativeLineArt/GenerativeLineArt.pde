// Generative Line Art  -  pen plotter edition
// ------------------------------------------------------------------
// Processing 4 (Java mode). No extra libraries needed.
//
// * 17 patterns, up to 4 independent pen layers (each: pattern, seed,
//   pen colour, pen width, scale / rotate / offset)
// * live preview while you drag the sliders
// * SVG export in millimetres, one Inkscape layer per pen (or one file
//   per pen), with optional pen-travel optimisation
// * presets: save / load the complete setup as a .json file
//
// Keys:  S  quick-save SVG into the "exports" folder next to this sketch
//        P  quick-save preset into "presets"      L  load preset...
//        N / Space  new seed      R  randomize the current pattern
//        1-4  select layer        Left / Right  previous / next pattern
// Mouse wheel over a slider = fine adjustment.

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
  "Hilbert curve", "Sunburst"
};
final String[] PAPER_NAMES = { "A5", "A4", "A3", "Square" };
final float[][] PAPER_MM   = { {148, 210}, {210, 297}, {297, 420}, {250, 250} };
final String[] PEN_NAMES   = { "Black", "Red", "Blue", "Green", "Orange", "Purple", "Teal", "Brown" };
final int[] PEN_COLORS     = { 0xFF111111, 0xFFD62828, 0xFF1D4ED8, 0xFF15803D, 0xFFEA7A00, 0xFF7E22CE, 0xFF0E9AA7, 0xFF7C4A21 };
final int NUM_LAYERS = 4;

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
Layer[] layers = new Layer[NUM_LAYERS];
int curLayer = 0;
Layer gen;                         // layer that is currently being generated

ArrayList<Widget> panelFlat = new ArrayList<Widget>();
Widget activeW = null;
Param activeParam = null;
boolean ddOpen = false;            // pattern dropdown open?

boolean previewStale = true;       // geometry changed -> redraw preview image
float genW = 210, genH = 297;      // page size in mm
float xmin, xmax, ymin, ymax;      // drawing area inside the margin
PGraphics pg;

File pendingExport, pendingPresetSave, pendingPresetLoad;
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
  pOptimize.geometry = false;
  pSeparate.geometry = false;
  layers[0] = new Layer(0, 0, 0, true, 1234);
  layers[1] = new Layer(1, 3, 1, false, 42);
  layers[2] = new Layer(2, 2, 2, false, 7);
  layers[3] = new Layer(3, 4, 3, false, 99);
}

void draw() {
  background(C_CANVAS);
  if (pendingExport != null)     { File f = pendingExport;     pendingExport = null;     writeSVG(f); }
  if (pendingPresetSave != null) { File f = pendingPresetSave; pendingPresetSave = null; savePreset(f); }
  if (pendingPresetLoad != null) { File f = pendingPresetLoad; pendingPresetLoad = null; loadPreset(f); }

  updatePage();
  for (Layer L : layers) {
    if (L.dirty && L.pEnabled.on()) { L.dirty = false; generateLayer(L); previewStale = true; }
  }
  buildPanel();
  drawPaper();
  drawPanel();
  drawStatusBar();
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
    if (!geometry) previewStale = true;
    else if (owner == null) { for (Layer L : layers) L.dirty = true; }
    else owner.dirty = true;
  }
  int i() { return round(val); }
  boolean on() { return val > 0.5; }
}

class Layer {
  int id;
  Param pEnabled, pColor, pPen, pMode, pSeed, pScale, pRot, pOffX, pOffY;
  ArrayList<ArrayList<Param>> modeParams = new ArrayList<ArrayList<Param>>();
  ArrayList<ArrayList<PVector>> paths = new ArrayList<ArrayList<PVector>>();
  boolean dirty = true;
  int nPaths, nPoints;
  float length;

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
    pEnabled.geometry = false; pColor.geometry = false; pPen.geometry = false;
    for (int m = 0; m < PATTERN_NAMES.length; m++) modeParams.add(makeParams(this, m));
  }
  ArrayList<Param> params() { return modeParams.get(pMode.i()); }
  int penColor() { return PEN_COLORS[pColor.i()]; }
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
  }
  return l;
}

float pv(int i) { return gen.params().get(i).val; }

void randomizeLayer(Layer L) {
  L.pSeed.set(ui.nextInt(10000));
  for (Param p : L.params()) {
    if (p.type == 1) continue;
    float lo = p.min + 0.08 * (p.max - p.min);
    float hi = p.min + 0.75 * (p.max - p.min);
    p.set(lo + ui.nextFloat() * (hi - lo));
  }
}

void resetLayer(Layer L) {
  for (Param p : L.params()) p.set(p.def);
}

// ---------- actions -------------------------------------------------------
void action(int id) {
  Layer L = layers[curLayer];
  switch (id) {
    case 0: L.pSeed.set(ui.nextInt(10000)); break;
    case 1: randomizeLayer(L); break;
    case 2: resetLayer(L); break;
    case 3: requestExport(); break;
    case 4: requestPresetSave(); break;
    case 5: requestPresetLoad(); break;
  }
}

void keyPressed() {
  Layer L = layers[curLayer];
  if (key == CODED) {
    if (keyCode == RIGHT) L.pMode.set((L.pMode.i() + 1) % PATTERN_NAMES.length);
    else if (keyCode == LEFT) L.pMode.set((L.pMode.i() + PATTERN_NAMES.length - 1) % PATTERN_NAMES.length);
    return;
  }
  if (key == 's' || key == 'S') quickSave();
  else if (key == 'p' || key == 'P') quickSavePreset();
  else if (key == 'l' || key == 'L') requestPresetLoad();
  else if (key == 'n' || key == 'N' || key == ' ') L.pSeed.set(ui.nextInt(10000));
  else if (key == 'r' || key == 'R') randomizeLayer(L);
  else if (key >= '1' && key <= '0' + NUM_LAYERS) curLayer = key - '1';
}

// ---------- GUI widgets ---------------------------------------------------
abstract class Widget {
  float x, y, w, h;
  Param p;                       // parameter this widget edits (if any)
  abstract void display();
  void press() {}
  void drag() {}
  boolean hit() { return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h; }
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

float stack(ArrayList<Widget> ws, float y) {
  for (Widget w : ws) {
    w.x = PAD; w.w = PANEL_W - 2 * PAD; w.y = y;
    if (w instanceof RowW) {
      RowW r = (RowW) w;
      r.arrange();
      for (Widget k : r.kids) panelFlat.add(k);
    } else panelFlat.add(w);
    y += w.h + GAP;
  }
  return y;
}

void buildPanel() {
  Layer L = layers[curLayer];
  ArrayList<Widget> top = new ArrayList<Widget>();
  top.add(new ChoiceW(pPaper, 4, pLandscape));
  top.add(new SliderW(pMargin));
  top.add(new Header("PEN LAYERS  (each layer = one pen)"));
  top.add(new LayerTabsW());
  top.add(new RowW(new Widget[] { new ToggleW(L.pEnabled), new SwatchW(L.pColor) }, new float[] { 1, 2 }));
  top.add(new DropdownW(L.pMode));
  top.add(row(new SliderW(L.pPen), new SliderW(L.pSeed)));
  top.add(new ButtonRow(new String[] { "New seed", "Randomize", "Reset" }, new int[] { 0, 1, 2 }));
  top.add(new Header("PATTERN PARAMETERS"));

  Widget pending = null;
  for (Param p : L.params()) {
    Widget wd = p.type == 1 ? new ToggleW(p) : (p.type == 2 ? new ChoiceW(p, p.opts.length, null) : new SliderW(p));
    if (p.wide) {
      if (pending != null) { top.add(new RowW(new Widget[] { pending }, new float[] { 1, 1 })); pending = null; }
      top.add(wd);
    } else if (pending == null) pending = wd;
    else { top.add(row(pending, wd)); pending = null; }
  }
  if (pending != null) top.add(new RowW(new Widget[] { pending }, new float[] { 1, 1 }));

  top.add(new Header("LAYER TRANSFORM"));
  top.add(row(new SliderW(L.pScale), new SliderW(L.pRot)));
  top.add(row(new SliderW(L.pOffX), new SliderW(L.pOffY)));

  ArrayList<Widget> bottom = new ArrayList<Widget>();
  bottom.add(new ButtonRow(new String[] { "Save preset...", "Load preset..." }, new int[] { 4, 5 }));
  bottom.add(row(new ToggleW(pOptimize), new ToggleW(pSeparate)));
  Widget exp = new ButtonRow(new String[] { "Export SVG..." }, new int[] { 3 });
  exp.h = 36;
  bottom.add(exp);

  panelFlat = new ArrayList<Widget>();
  stack(top, 44);
  float bh = 0;
  for (Widget w : bottom) bh += w.h + GAP;
  stack(bottom, height - PAD - bh + GAP);
}

void drawPanel() {
  noStroke(); fill(C_PANEL); rect(0, 0, PANEL_W, height);
  fill(C_TEXT); textSize(16); textAlign(LEFT, TOP); text("Generative Line Art", PAD, 14);
  for (Widget w : panelFlat) w.display();

  // hint text above the bottom group
  float by = height;
  for (Widget w : panelFlat) if (w instanceof ButtonRow && ((ButtonRow) w).ids[0] == 4) by = w.y;
  fill(C_DIM); textSize(11); textAlign(LEFT, BOTTOM);
  text("S save SVG | P save preset | L load | N seed | R randomize\n1-4 layer | arrows = pattern | wheel over slider = fine", PAD, by - 8);

  for (Widget w : panelFlat) if (w instanceof DropdownW) ((DropdownW) w).overlay();
}

String fmtParam(Param p) {
  if (p.isInt) return str(p.i());
  float a = abs(p.val);
  return String.format(Locale.US, a >= 100 ? "%.0f" : (a >= 10 ? "%.1f" : (a >= 1 ? "%.2f" : "%.3f")), p.val);
}

void mousePressed() {
  if (ddOpen) {
    for (Widget w : panelFlat) if (w instanceof DropdownW) ((DropdownW) w).clickItem();
    ddOpen = false;
    return;
  }
  if (mouseX > PANEL_W) return;
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
    }
  }
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
  int paths = 0, pts = 0, active = 0; float len = 0;
  for (Layer L : layers) if (L.pEnabled.on()) { active++; paths += L.nPaths; pts += L.nPoints; len += L.length; }
  textSize(12); textAlign(LEFT, CENTER); fill(C_DIM);
  String info = PAPER_NAMES[pPaper.i()] + " " + (int) genW + " x " + (int) genH + " mm  |  "
    + active + (active == 1 ? " layer  |  " : " layers  |  ") + paths + " paths  |  " + pts + " points  |  pen-down "
    + String.format(Locale.US, "%.1f", len / 1000.0) + " m";
  text(info, PANEL_W + 14, height - 12);
  if (millis() - statusMs < 6000) {
    fill(C_ACCENT); textAlign(RIGHT, CENTER);
    text(status, width - 14, height - 12);
  }
}

void setStatus(String s) { status = s; statusMs = millis(); }

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
  L.paths = out;

  L.nPaths = out.size(); L.nPoints = 0; L.length = 0;
  for (ArrayList<PVector> p : out) {
    L.nPoints += p.size();
    for (int i = 1; i < p.size(); i++) L.length += PVector.dist(p.get(i - 1), p.get(i));
  }
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
  for (int it = 0; it < smooth && pts.size() < 150000; it++) {   // Chaikin corner cutting
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
  emit(out, pts);
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

// ---------- SVG export ----------------------------------------------------
String timestamp() {
  return year() + nf(month(), 2) + nf(day(), 2) + "_" + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2);
}

String slug(String s) { return s.toLowerCase().replace(' ', '_'); }

void requestExport() {
  selectOutput("Save SVG for plotter", "svgSelected", new File(sketchPath("lineart_" + timestamp() + ".svg")));
}

void svgSelected(File f) {
  if (f == null) return;                       // dialog cancelled
  if (!f.getName().toLowerCase().endsWith(".svg")) f = new File(f.getAbsolutePath() + ".svg");
  pendingExport = f;                           // handled on the animation thread
}

void quickSave() {
  File dir = new File(sketchPath("exports"));
  dir.mkdirs();
  pendingExport = new File(dir, "lineart_" + timestamp() + ".svg");
}

// Nearest-neighbour ordering (and reversing) of paths to minimise pen-up travel.
ArrayList<ArrayList<PVector>> optimizeOrder(ArrayList<ArrayList<PVector>> in) {
  ArrayList<ArrayList<PVector>> rem = new ArrayList<ArrayList<PVector>>(in);
  ArrayList<ArrayList<PVector>> out = new ArrayList<ArrayList<PVector>>(in.size());
  float cx = 0, cy = 0;
  while (!rem.isEmpty()) {
    int best = 0; boolean rev = false; float bd = Float.MAX_VALUE;
    for (int i = 0; i < rem.size(); i++) {
      ArrayList<PVector> p = rem.get(i);
      PVector a = p.get(0), b = p.get(p.size() - 1);
      float da = sq(a.x - cx) + sq(a.y - cy);
      float db = sq(b.x - cx) + sq(b.y - cy);
      if (da < bd) { bd = da; best = i; rev = false; }
      if (db < bd) { bd = db; best = i; rev = true; }
    }
    ArrayList<PVector> p = rem.get(best);
    rem.set(best, rem.get(rem.size() - 1));
    rem.remove(rem.size() - 1);
    if (rev) { p = new ArrayList<PVector>(p); Collections.reverse(p); }
    out.add(p);
    PVector e = p.get(p.size() - 1);
    cx = e.x; cy = e.y;
  }
  return out;
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

void writeSVG(File f) {
  ArrayList<Layer> act = new ArrayList<Layer>();
  for (Layer L : layers) if (L.pEnabled.on() && !L.paths.isEmpty()) act.add(L);
  if (act.isEmpty()) { setStatus("Nothing to export: no visible lines"); return; }

  if (pSeparate.on() && act.size() > 1) {
    String base = f.getAbsolutePath();
    if (base.toLowerCase().endsWith(".svg")) base = base.substring(0, base.length() - 4);
    for (Layer L : act) {
      ArrayList<Layer> one = new ArrayList<Layer>();
      one.add(L);
      writeSvgFile(new File(base + "_layer" + (L.id + 1) + "_" + slug(PATTERN_NAMES[L.pMode.i()]) + ".svg"), one);
    }
    setStatus("Saved " + act.size() + " files (one per layer)");
  } else {
    writeSvgFile(f, act);
    setStatus("Saved " + f.getName() + " (" + act.size() + (act.size() == 1 ? " layer" : " layers") + ")");
  }
}

void writeSvgFile(File f, ArrayList<Layer> ls) {
  boolean opt = pOptimize.on();
  StringBuilder sb = new StringBuilder(1 << 20);
  sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n");
  sb.append("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:inkscape=\"http://www.inkscape.org/namespaces/inkscape\" width=\"");
  appendNum(sb, genW); sb.append("mm\" height=\""); appendNum(sb, genH); sb.append("mm\" viewBox=\"0 0 ");
  appendNum(sb, genW); sb.append(' '); appendNum(sb, genH); sb.append("\">\n");
  for (Layer L : ls) {
    ArrayList<ArrayList<PVector>> ps = opt ? optimizeOrder(L.paths) : L.paths;
    sb.append("<g id=\"layer").append(L.id + 1).append("\" inkscape:groupmode=\"layer\" inkscape:label=\"")
      .append(L.id + 1).append(' ').append(PATTERN_NAMES[L.pMode.i()]).append(' ').append(PEN_NAMES[L.pColor.i()])
      .append("\" fill=\"none\" stroke=\"#").append(hex(L.penColor(), 6)).append("\" stroke-width=\"");
    appendNum(sb, L.pPen.val); sb.append("\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n");
    for (ArrayList<PVector> p : ps) {
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
  saveStrings(f, new String[] { sb.toString() });
  println("SVG saved: " + f.getAbsolutePath());
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
