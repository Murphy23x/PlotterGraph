// Share image: a PNG "proof card" of the design, to show a client or post
// online: the plot on paper at the real pen widths, with a soft shadow and a
// caption (patterns, paper, pens, plot time). The I key or the Output tab
// button saves one; on the command line, --out name.png writes it.

File pendingShare;

void requestShareImage() {
  selectOutput("Save a PNG image of the design", "shareSelected", new File(sketchPath("lineart_" + timestamp() + ".png")));
}

void shareSelected(File f) {
  if (f == null) return;
  if (!f.getName().toLowerCase().endsWith(".png")) f = new File(f.getAbsolutePath() + ".png");
  pendingShare = f;
}

// Renders the card; longSide is the long edge of the paper in pixels.
PGraphics shareImage(int longSide) {
  float k = longSide / max(genW, genH);
  int pw = round(genW * k), ph = round(genH * k);
  int pad = round(longSide * 0.08), foot = round(longSide * 0.11);
  int w = pw + 2 * pad, h = ph + pad + foot;
  PGraphics g = createGraphics(w, h, JAVA2D);
  g.smooth(8);
  g.beginDraw();
  g.background(0xFFE9E6E0);
  // soft shadow
  g.noStroke();
  for (int i = 12; i >= 1; i--) {
    g.fill(0, 5);
    float o = i * longSide / 900.0;
    g.rect(pad - o * 0.5 + o * 0.4, pad - o * 0.5 + o * 0.9, pw + o, ph + o, o);
  }
  g.fill(paperColor()); g.rect(pad, pad, pw, ph);
  g.pushMatrix();
  g.translate(pad, pad);
  g.noFill(); g.strokeJoin(ROUND); g.strokeCap(ROUND);
  for (Layer L : layers) {
    if (!L.pEnabled.on()) continue;
    g.stroke(L.penColor());
    g.strokeWeight(max(1, L.pPen.val * k));
    for (ArrayList<PVector> path : L.paths) {
      g.beginShape();
      for (PVector v : path) g.vertex(v.x * k, v.y * k);
      g.endShape();
    }
  }
  g.popMatrix();

  // caption
  ArrayList<String> pats = new ArrayList<String>();
  int pens = 0; float secs = 0, len = 0;
  for (Layer L : layers) if (L.pEnabled.on()) {
    pens++; secs += L.seconds(); len += L.length;
    String n = PATTERN_NAMES[L.pMode.i()];
    if (!pats.contains(n)) pats.add(n);
  }
  float ts = longSide * 0.026, ty = pad + ph + foot * 0.42;
  g.textFont(uiFont);
  g.textAlign(LEFT, CENTER);
  // the caption shrinks to stay clear of the pen swatches on the right
  float r = ts * 0.55, room = pw - pens * r * 2.8 - r;
  String title = pats.isEmpty() ? "Empty design" : join(pats.toArray(new String[0]), "  +  ");
  String info = PAPER_NAMES[pPaper.i()] + (pLandscape.on() ? " landscape" : "") + "  ·  " + round(genW) + " × " + round(genH) + " mm  ·  "
    + pens + (pens == 1 ? " pen" : " pens") + "  ·  " + String.format(Locale.US, "%.1f m of line", len / 1000) + "  ·  plot time " + fmtTime(secs).replace("~", "about ");
  g.fill(0xFF2A2A2A); g.textSize(ts);
  if (g.textWidth(title) > room) g.textSize(max(ts * 0.4, ts * room / g.textWidth(title)));
  g.text(title, pad, ty);
  g.fill(0xFF77736C); g.textSize(ts * 0.62);
  if (g.textWidth(info) > room) g.textSize(max(ts * 0.3, ts * 0.62 * room / g.textWidth(info)));
  g.text(info, pad, ty + ts * 1.15);
  // pen swatches, right-aligned
  float x = pad + pw - r;
  for (int i = NUM_LAYERS - 1; i >= 0; i--) {
    Layer L = layers[i];
    if (!L.pEnabled.on()) continue;
    g.stroke(0, 50); g.strokeWeight(max(1, r * 0.08)); g.fill(L.penColor()); g.ellipse(x, ty, r * 2, r * 2);
    x -= r * 2.8;
  }
  g.endDraw();
  return g;
}

boolean writeShareImage(File f) {
  regenerate();
  PGraphics g = shareImage(2000);
  if (f.getParentFile() != null) f.getParentFile().mkdirs();
  boolean ok = g.save(f.getAbsolutePath());
  setStatus(ok ? "Saved image: " + f.getName() : "Could not save " + f.getName());
  return ok;
}
