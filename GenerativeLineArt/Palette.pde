// Command palette: Ctrl+K (Cmd+K) or / opens a search box over everything
// the app can do: patterns, actions, paper, pens, layers, tabs, sources and
// the presets in presets/. Type a few letters, Up/Down to choose, Enter to
// run, Esc to close. The keyboard shortcut of each command is shown, so the
// palette doubles as the shortcut reference.

class Cmd {
  String label, hint;
  Runnable run;
  Cmd(String label, String hint, Runnable run) { this.label = label; this.hint = hint; this.run = run; }
}

boolean paletteOn = false;
String paletteQuery = "";
int paletteSel = 0, paletteTop = 0;
ArrayList<Cmd> paletteAll = new ArrayList<Cmd>();
final int PALETTE_ROWS = 12;

void openPalette() {
  paletteAll = buildCommands();
  paletteQuery = ""; paletteSel = 0; paletteTop = 0;
  paletteOn = true;
  focusText = null; ddOpen = false; fontOpen = false;
}

Cmd cmd(String label, String hint, Runnable r) { return new Cmd(label, hint, r); }
Runnable act(final int id) { return new Runnable() { public void run() { action(id); } }; }

ArrayList<Cmd> buildCommands() {
  ArrayList<Cmd> c = new ArrayList<Cmd>();
  final Layer L = layers[curLayer];
  c.add(cmd("Export " + FORMAT_NAMES[pFormat.i()] + "...", "S", act(3)));
  c.add(cmd("Simulate plot", "G", new Runnable() { public void run() { toggleSimulation(); } }));
  c.add(cmd("Explore variations", "E", new Runnable() { public void run() { toggleExplore(); } }));
  c.add(cmd("New seed", "N / Space", act(0)));
  c.add(cmd("Randomize layer", "R", act(1)));
  c.add(cmd("Reset layer", "", act(2)));
  c.add(cmd("Undo", "Ctrl+Z", act(6)));
  c.add(cmd("Redo", "Ctrl+Y", act(7)));
  c.add(cmd("Save preset...", "P", act(4)));
  c.add(cmd("Load preset...", "L", act(5)));
  c.add(cmd("Start fresh (new design)", "Ctrl+N", new Runnable() { public void run() { startFresh(); } }));
  c.add(cmd("Batch export seed variations", "", act(8)));
  c.add(cmd("Fit preview to window", "0 / double-click", new Runnable() { public void run() { resetView(); } }));
  c.add(cmd("Zoom in", "+ / wheel", new Runnable() { public void run() { zoomAt(PANEL_W + areaW() / 2, areaH() / 2, 1.5); } }));
  c.add(cmd("Zoom out", "- / wheel", new Runnable() { public void run() { zoomAt(PANEL_W + areaW() / 2, areaH() / 2, 1 / 1.5); } }));
  c.add(cmd("Toggle landscape", "", new Runnable() { public void run() { pLandscape.set(pLandscape.on() ? 0 : 1); } }));
  for (int i = 0; i < PAPER_NAMES.length; i++) {
    final int p = i;
    c.add(cmd("Paper: " + PAPER_NAMES[i], "", new Runnable() { public void run() { pPaper.set(p); } }));
  }
  for (int i = 0; i < PATTERN_NAMES.length; i++) {
    final int m = i;
    c.add(cmd("Pattern: " + PATTERN_NAMES[i], "arrows", new Runnable() { public void run() { L.pMode.set(m); L.pEnabled.set(1); panelTab = 0; } }));
  }
  for (int i = 0; i < NUM_LAYERS; i++) {
    final int n = i;
    c.add(cmd("Layer " + (i + 1) + (layers[i].pEnabled.on() ? "" : " (off)") + ": " + PATTERN_NAMES[layers[i].pMode.i()], str(i + 1),
      new Runnable() { public void run() { curLayer = n; panelTab = 0; } }));
  }
  c.add(cmd((L.pEnabled.on() ? "Disable" : "Enable") + " layer " + (curLayer + 1), "", new Runnable() { public void run() { L.pEnabled.set(L.pEnabled.on() ? 0 : 1); } }));
  for (int i = 0; i < PEN_NAMES.length; i++) {
    final int p = i;
    c.add(cmd("Pen colour: " + PEN_NAMES[i] + " (layer " + (curLayer + 1) + ")", "", new Runnable() { public void run() { L.pColor.set(p); } }));
  }
  for (int i = 0; i < FORMAT_NAMES.length; i++) {
    final int f = i;
    c.add(cmd("Export format: " + FORMAT_NAMES[i], "", new Runnable() { public void run() { pFormat.set(f); } }));
  }
  String[] tabs = { "Design", "Sources", "Output" };
  for (int i = 0; i < tabs.length; i++) {
    final int t = i;
    c.add(cmd("Go to " + tabs[i] + " tab", "", new Runnable() { public void run() { panelTab = t; panelScroll = 0; } }));
  }
  c.add(cmd("Load photo / image...", "or drop it", act(9)));
  c.add(cmd("Load GPX / GeoJSON route...", "or drop it", act(13)));
  c.add(cmd("Load CSV / JSON data...", "or drop it", act(14)));
  c.add(cmd("Load SVG...", "or drop it", act(15)));
  c.add(cmd("Load audio...", "or drop it", act(16)));
  c.add(cmd("Load grid / DEM...", "or drop it", act(17)));
  c.add(cmd("Fetch streets (" + tvLocation.s + ")", "", act(18)));
  c.add(cmd("Fetch terrain (" + tvLocation.s + ")", "", act(19)));
  c.add(cmd("Fetch weather (" + tvLocation.s + ")", "", act(20)));
  c.add(cmd("Choose watch folder...", "or drop a folder", act(23)));
  c.add(cmd("Clear sources", "", act(27)));
  File[] ps = new File(sketchPath("presets")).listFiles();
  if (ps != null) {
    Arrays.sort(ps);
    for (final File f : ps) {
      if (!f.getName().toLowerCase().endsWith(".json")) continue;
      String nm = f.getName().replaceAll("\\.json$", "").replace('_', ' ');
      c.add(cmd("Preset: " + nm, "", new Runnable() { public void run() { loadPreset(f); } }));
    }
  }
  return c;
}

// Commands whose label contains every typed word; labels that start with
// the query come first.
ArrayList<Cmd> paletteMatches() {
  ArrayList<Cmd> first = new ArrayList<Cmd>(), rest = new ArrayList<Cmd>();
  String q = paletteQuery.trim().toLowerCase();
  String[] words = q.isEmpty() ? new String[0] : splitTokens(q);
  for (Cmd c : paletteAll) {
    String l = c.label.toLowerCase();
    boolean ok = true;
    for (String w : words) if (!l.contains(w)) { ok = false; break; }
    if (!ok) continue;
    if (!q.isEmpty() && (l.startsWith(q) || l.contains(": " + q))) first.add(c); else rest.add(c);
  }
  first.addAll(rest);
  return first;
}

float[] paletteBox() {
  float w = min(560, width - 80), x = (width - w) / 2, y = 70;
  return new float[] { x, y, w, 46 + PALETTE_ROWS * 28 + 10 };
}

void drawPalette() {
  if (!paletteOn) return;
  noStroke(); fill(0, 120); rect(0, 0, width, height);
  float[] b = paletteBox();
  ArrayList<Cmd> m = paletteMatches();
  paletteSel = constrain(paletteSel, 0, max(0, m.size() - 1));
  if (paletteSel < paletteTop) paletteTop = paletteSel;
  if (paletteSel >= paletteTop + PALETTE_ROWS) paletteTop = paletteSel - PALETTE_ROWS + 1;
  float rows = min(PALETTE_ROWS, max(1, m.size()));
  fill(C_PANEL); stroke(C_TRACK); strokeWeight(1);
  rect(b[0], b[1], b[2], 56 + rows * 28, 8);
  noStroke(); fill(C_FIELD); rect(b[0] + 10, b[1] + 10, b[2] - 20, 32, 5);
  textSize(14); textAlign(LEFT, CENTER);
  if (paletteQuery.isEmpty()) { fill(C_DIM); text("Type a command, pattern or preset...", b[0] + 20, b[1] + 25); }
  else { fill(C_TEXT); text(paletteQuery, b[0] + 20, b[1] + 25); }
  if ((millis() / 500) % 2 == 0) { stroke(C_ACCENT); float cx = b[0] + 21 + (paletteQuery.isEmpty() ? 0 : textWidth(paletteQuery)); line(cx, b[1] + 16, cx, b[1] + 35); }
  textSize(13);
  if (m.isEmpty()) { noStroke(); fill(C_DIM); textAlign(LEFT, CENTER); text("No matching command", b[0] + 20, b[1] + 66); return; }
  for (int r = 0; r < rows && paletteTop + r < m.size(); r++) {
    Cmd c = m.get(paletteTop + r);
    float ry = b[1] + 50 + r * 28;
    boolean sel = paletteTop + r == paletteSel;
    noStroke();
    if (sel) { fill(C_ACCENT, 60); rect(b[0] + 6, ry, b[2] - 12, 26, 4); }
    fill(sel ? C_TEXT : color(205)); textAlign(LEFT, CENTER);
    text(c.label, b[0] + 18, ry + 13);
    if (!c.hint.isEmpty()) { fill(C_DIM); textAlign(RIGHT, CENTER); textSize(11); text(c.hint, b[0] + b[2] - 18, ry + 13); textSize(13); }
  }
  if (m.size() > PALETTE_ROWS) {
    fill(C_DIM); textSize(10); textAlign(RIGHT, TOP);
    text((paletteTop + 1) + "-" + min(m.size(), paletteTop + PALETTE_ROWS) + " of " + m.size(), b[0] + b[2] - 12, b[1] + 56 + rows * 28 + 4);
  }
}

void paletteKey() {
  if (key == ESC) { key = 0; paletteOn = false; return; }
  ArrayList<Cmd> m = paletteMatches();
  if (key == CODED) {
    if (keyCode == UP) paletteSel = max(0, paletteSel - 1);
    else if (keyCode == DOWN) paletteSel = min(m.size() - 1, paletteSel + 1);
    return;
  }
  if (key == ENTER || key == RETURN) { if (!m.isEmpty()) runCmd(m.get(paletteSel)); return; }
  if (key == BACKSPACE) { if (paletteQuery.length() > 0) paletteQuery = paletteQuery.substring(0, paletteQuery.length() - 1); paletteSel = 0; return; }
  boolean ctrl = keyEvent != null && (keyEvent.isControlDown() || keyEvent.isMetaDown());
  if (ctrl && keyCode == 'K') { paletteOn = false; return; }
  if (ctrl && keyCode == 'V') { String c = clipboardText(); if (c != null) paletteQuery += c.trim(); return; }
  if (key >= 32 && key != DELETE && paletteQuery.length() < 60) { paletteQuery += key; paletteSel = 0; paletteTop = 0; }
}

void runCmd(Cmd c) {
  paletteOn = false;
  c.run.run();
  if (millis() - statusMs > 100) setStatus(c.label);
}

void palettePress() {
  float[] b = paletteBox();
  ArrayList<Cmd> m = paletteMatches();
  int r = floor((mouseY - b[1] - 50) / 28);
  if (mouseX >= b[0] && mouseX <= b[0] + b[2] && r >= 0 && r < PALETTE_ROWS && paletteTop + r < m.size()) runCmd(m.get(paletteTop + r));
  else if (mouseX < b[0] || mouseX > b[0] + b[2] || mouseY < b[1] || mouseY > b[1] + 56 + PALETTE_ROWS * 28) paletteOn = false;
}

void paletteWheel(int n) { paletteSel = constrain(paletteSel + n, 0, max(0, paletteMatches().size() - 1)); }
