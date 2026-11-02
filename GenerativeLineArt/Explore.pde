// Explore: a 3 x 3 grid of variations of the current layer, drawn on the
// page together with the other layers. Click one to keep it (Undo takes it
// back). "Seeds" only changes the seed; "Mix" also varies the pattern's
// parameters, like Randomize (locked values stay). One variation is
// generated per frame, so the window stays responsive.
//   E = open / close, Space or R = new batch, Tab = Seeds / Mix, Esc = close

final int EX_N = 9;
boolean exploreOn = false;
int exploreMix = 0;                   // 0 = seeds, 1 = mix parameters
int exploreDone = 0;                  // variations generated so far
int exploreLayer = 0;
int exploreBatch = 0;
float[][] exVals = new float[EX_N][];   // per variation: seed, then the pattern's parameters
PGraphics[] exThumb = new PGraphics[EX_N];
int[] exPaths = new int[EX_N];
float[] exSecs = new float[EX_N];

void toggleExplore() {
  if (exploreOn) { exploreOn = false; return; }
  exploreOn = true;
  newExploreBatch();
}

void newExploreBatch() {
  exploreLayer = curLayer;
  exploreBatch++;
  Layer L = layers[exploreLayer];
  Random r = new Random(L.pSeed.i() * 7919L + exploreBatch * 104729L + exploreMix);
  ArrayList<Param> ps = L.params();
  for (int v = 0; v < EX_N; v++) {
    float[] a = new float[ps.size() + 1];
    a[0] = L.pSeed.locked ? L.pSeed.val : r.nextInt(10000);
    for (int k = 0; k < ps.size(); k++) {
      Param p = ps.get(k);
      a[k + 1] = p.val;
      if (exploreMix == 1 && p.type != 1 && !p.locked) {
        float lo = p.min + 0.08 * (p.max - p.min), hi = p.min + 0.75 * (p.max - p.min);
        a[k + 1] = lo + r.nextFloat() * (hi - lo);
        if (p.isInt) a[k + 1] = round(a[k + 1]);
      }
    }
    if (v == 0) {                       // the first cell is the current design, for comparison
      a[0] = L.pSeed.val;
      for (int k = 0; k < ps.size(); k++) a[k + 1] = ps.get(k).val;
    }
    exVals[v] = a;
    exThumb[v] = null;
  }
  exploreDone = 0;
}

// Generates the next variation (called once per frame while exploring).
void exploreStep() {
  if (!exploreOn || exploreDone >= EX_N) return;
  if (curLayer != exploreLayer || !layers[exploreLayer].pEnabled.on()) { exploreOn = false; return; }
  Layer L = layers[exploreLayer];
  ArrayList<Param> ps = L.params();
  int v = exploreDone;
  // try the variation's values without touching undo, then put everything back
  float seed0 = L.pSeed.val;
  float[] old = new float[ps.size()];
  for (int k = 0; k < ps.size(); k++) old[k] = ps.get(k).val;
  ArrayList<ArrayList<PVector>> paths0 = L.paths;
  int n0 = L.nPaths, p0 = L.nPoints; float len0 = L.length, tr0 = L.travel;
  L.pSeed.val = exVals[v][0];
  for (int k = 0; k < ps.size(); k++) ps.get(k).val = exVals[v][k + 1];
  generateLayer(L);
  exPaths[v] = L.nPaths;
  exSecs[v] = L.seconds();
  exThumb[v] = renderThumb(L, L.paths);
  L.pSeed.val = seed0;
  for (int k = 0; k < ps.size(); k++) ps.get(k).val = old[k];
  L.paths = paths0; L.nPaths = n0; L.nPoints = p0; L.length = len0; L.travel = tr0;
  exploreDone++;
}

float[] exCell(int v) {               // x, y, w, h of a cell in the preview area
  float gx = PANEL_W + 30, gy = 56, gw = areaW() - 60, gh = areaH() - 80;
  float cw = gw / 3, ch = gh / 3;
  return new float[] { gx + (v % 3) * cw, gy + (v / 3) * ch, cw, ch };
}

PGraphics renderThumb(Layer cur, ArrayList<ArrayList<PVector>> paths) {
  float[] c = exCell(0);
  float k = min((c[2] - 16) / genW, (c[3] - 30) / genH);
  int tw = max(1, round(genW * k)), th = max(1, round(genH * k));
  PGraphics g = createGraphics(tw, th, JAVA2D);
  g.beginDraw();
  g.background(paperColor());
  g.noFill(); g.strokeJoin(ROUND); g.strokeCap(ROUND);
  for (Layer L : layers) {
    if (!L.pEnabled.on()) continue;
    g.stroke(L.penColor(), L == cur ? 255 : 90);
    g.strokeWeight(max(0.5, L.pPen.val * k));
    for (ArrayList<PVector> path : (L == cur ? paths : L.paths)) {
      g.beginShape();
      for (PVector p : path) g.vertex(p.x * k, p.y * k);
      g.endShape();
    }
  }
  g.endDraw();
  return g;
}

void drawExplore() {
  noStroke(); fill(C_CANVAS); rect(PANEL_W, 0, areaW(), areaH());
  fill(C_TEXT); textSize(14); textAlign(LEFT, CENTER);
  text((exploreMix == 0 ? "Seed variations" : "Mixed variations") + " of layer " + (exploreLayer + 1) + "  ·  " + PATTERN_NAMES[layers[exploreLayer].pMode.i()], PANEL_W + 30, 26);
  fill(C_DIM); textSize(11); textAlign(RIGHT, CENTER);
  text("click (or 1-9) to keep  ·  Space = more  ·  Tab = " + (exploreMix == 0 ? "also vary parameters" : "seeds only") + "  ·  Esc = close", width - 30, 26);
  for (int v = 0; v < EX_N; v++) {
    float[] c = exCell(v);
    boolean over = mouseX >= c[0] && mouseX < c[0] + c[2] && mouseY >= c[1] && mouseY < c[1] + c[3];
    if (exThumb[v] == null) {
      fill(C_DIM); textAlign(CENTER, CENTER); textSize(12);
      text(v == exploreDone ? "drawing..." : "", c[0] + c[2] / 2, c[1] + c[3] / 2);
      continue;
    }
    PGraphics t = exThumb[v];
    float tx = c[0] + (c[2] - t.width) / 2, ty = c[1] + 4;
    noStroke(); fill(0, 90); rect(tx + 3, ty + 4, t.width, t.height);
    image(t, tx, ty);
    if (over && exploreDone >= EX_N) { noFill(); stroke(C_ACCENT); strokeWeight(3); rect(tx - 2, ty - 2, t.width + 4, t.height + 4, 3); }
    fill(v == 0 ? C_ACCENT : C_DIM); textSize(11); textAlign(CENTER, TOP);
    String label = (v == 0 ? "current  ·  " : "seed " + (int) exVals[v][0] + "  ·  ") + exPaths[v] + " paths  ·  " + fmtTime(exSecs[v]);
    text(label, c[0] + c[2] / 2, ty + t.height + 5);
  }
}

// Mouse press while exploring: true when it was handled.
boolean explorePress() {
  if (!exploreOn || mouseX < PANEL_W) return false;
  for (int v = 0; v < EX_N; v++) {
    float[] c = exCell(v);
    if (mouseX >= c[0] && mouseX < c[0] + c[2] && mouseY >= c[1] && mouseY < c[1] + c[3] && exThumb[v] != null) {
      pickVariation(v);
      return true;
    }
  }
  return true;                          // clicks between the cells do nothing
}

void pickVariation(int v) {
  Layer L = layers[exploreLayer];
  commitPending();
  L.pSeed.set(exVals[v][0]);
  ArrayList<Param> ps = L.params();
  for (int k = 0; k < ps.size(); k++) ps.get(k).set(exVals[v][k + 1]);
  exploreOn = false;
  setStatus(v == 0 ? "Kept the current design" : "Variation applied (Ctrl+Z = back)");
}

// Keys while exploring: true when handled.
boolean exploreKey() {
  if (!exploreOn) return false;
  if (key == ESC || key == 'e' || key == 'E') { key = 0; exploreOn = false; return true; }
  if (key == ' ' || key == 'r' || key == 'R' || key == 'n' || key == 'N') { newExploreBatch(); return true; }
  if (key == TAB) { exploreMix = 1 - exploreMix; newExploreBatch(); return true; }
  if (key >= '1' && key <= '9' && exploreDone > key - '1') { pickVariation(key - '1'); return true; }
  return true;
}
