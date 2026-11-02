// Paper colour: preview the design on cream, kraft, grey, black or navy
// paper (with white, gold or silver gel pens on dark paper). It only
// changes the preview, the PNG image and the simulation; plot files never
// get a background. A pen that would barely show on the chosen paper is
// struck through in the pen swatches and named in the preview.

int paperColor() { return PAPER_COLOURS[pPaperCol.i()]; }

float lum(int c) { return 0.299 * red(c) + 0.587 * green(c) + 0.114 * blue(c); }

boolean lowContrast(int pen, int paper) {
  return abs(lum(pen) - lum(paper)) < 45 && dist(red(pen), green(pen), blue(pen), red(paper), green(paper), blue(paper)) < 110;
}

// A note above the page when an enabled pen barely shows on the paper.
void drawContrastWarning() {
  String w = "";
  for (Layer L : layers) {
    if (!L.pEnabled.on() || !lowContrast(L.penColor(), paperColor())) continue;
    w += (w.isEmpty() ? "" : ", ") + PEN_NAMES[L.pColor.i()] + " pen (layer " + (L.id + 1) + ")";
  }
  if (w.isEmpty()) return;
  String t = w + " barely shows on " + PAPER_COLOUR_NAMES[pPaperCol.i()].toLowerCase() + " paper";
  textSize(12);
  float tw = textWidth(t) + 24, x = PANEL_W + (areaW() - tw) / 2;
  noStroke(); fill(0xFF6B4A12); rect(x, 8, tw, 24, 12);
  fill(0xFFFFE3A3); textAlign(CENTER, CENTER); text(t, x + tw / 2, 19);
}
