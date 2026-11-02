// Zoom and pan in the preview: mouse wheel zooms around the cursor, drag
// pans, double-click (or 0) fits the page again. While zoomed in, the
// visible part is redrawn at that scale, at the real pen width, so you can
// check overlaps and fine detail before plotting.

float viewZoom = 1, viewCx = -1, viewCy = -1;   // view centre in page mm (-1 = page centre)
boolean panning = false;
float panLastX, panLastY;
PGraphics zoomPg;
String zoomKey = "";

float areaW() { return width - PANEL_W; }
float areaH() { return height - 24; }

// Fitted scale (px per mm) at zoom 1.
float fitScale() { return max(0.1, min((areaW() - 80) / genW, (areaH() - 80) / genH)); }

float viewK() { return fitScale() * viewZoom; }
float viewOx() { return PANEL_W + areaW() / 2 - (viewCx < 0 ? genW / 2 : min(viewCx, genW)) * viewK(); }
float viewOy() { return areaH() / 2 - (viewCy < 0 ? genH / 2 : min(viewCy, genH)) * viewK(); }

void resetView() { viewZoom = 1; viewCx = -1; viewCy = -1; }

void zoomAt(float mx, float my, float factor) {
  float k = viewK(), ox = viewOx(), oy = viewOy();
  float mmx = (mx - ox) / k, mmy = (my - oy) / k;              // page point under the cursor
  viewZoom = constrain(viewZoom * factor, 1, 40);
  if (viewZoom <= 1.0001) { resetView(); return; }
  float k2 = viewK();
  viewCx = constrain((PANEL_W + areaW() / 2 - (mx - mmx * k2)) / k2, 0, genW);
  viewCy = constrain((areaH() / 2 - (my - mmy * k2)) / k2, 0, genH);
}

void panBy(float dx, float dy) {
  if (viewZoom <= 1) return;
  float k = viewK();
  viewCx = constrain((viewCx < 0 ? genW / 2 : viewCx) - dx / k, 0, genW);
  viewCy = constrain((viewCy < 0 ? genH / 2 : viewCy) - dy / k, 0, genH);
}

boolean inPreview() { return mouseX > PANEL_W && mouseY < areaH(); }

// Draws the zoomed view into a buffer the size of the preview area.
void drawZoomed(float ox, float oy, float k) {
  int aw = max(1, (int) areaW()), ah = max(1, (int) areaH());
  String key = aw + "," + ah + "," + ox + "," + oy + "," + k;
  if (zoomPg == null || zoomPg.width != aw || zoomPg.height != ah || previewStale || !key.equals(zoomKey)) {
    if (zoomPg == null || zoomPg.width != aw || zoomPg.height != ah) zoomPg = createGraphics(aw, ah, JAVA2D);
    zoomPg.beginDraw();
    zoomPg.background(C_CANVAS);
    zoomPg.translate(ox - PANEL_W, oy);
    zoomPg.noStroke(); zoomPg.fill(0, 90); zoomPg.rect(5, 6, genW * k, genH * k);
    zoomPg.fill(255); zoomPg.rect(0, 0, genW * k, genH * k);
    zoomPg.noFill(); zoomPg.strokeJoin(ROUND); zoomPg.strokeCap(ROUND);
    float vx0 = (PANEL_W - ox) / k, vy0 = -oy / k, vx1 = vx0 + aw / k, vy1 = vy0 + ah / k;   // visible page area (mm)
    for (Layer L : layers) {
      if (!L.pEnabled.on()) continue;
      zoomPg.stroke(L.penColor());
      zoomPg.strokeWeight(max(0.8, L.pPen.val * k));
      for (ArrayList<PVector> path : L.paths) {
        if (!pathVisible(path, vx0, vy0, vx1, vy1)) continue;
        zoomPg.beginShape();
        for (PVector v : path) zoomPg.vertex(v.x * k, v.y * k);
        zoomPg.endShape();
      }
    }
    zoomPg.endDraw();
    zoomKey = key;
    previewStale = false;
  }
  image(zoomPg, PANEL_W, 0);
}

boolean pathVisible(ArrayList<PVector> p, float x0, float y0, float x1, float y1) {
  float a = 1e9, b = 1e9, c = -1e9, d = -1e9;
  for (PVector v : p) { a = min(a, v.x); b = min(b, v.y); c = max(c, v.x); d = max(d, v.y); }
  return c >= x0 && a <= x1 && d >= y0 && b <= y1;
}

// Zoom level and a 10 mm scale bar in the corner of the preview.
void drawZoomInfo(float k) {
  if (viewZoom <= 1) return;
  float bar = 10 * k, x = width - 20 - bar, y = areaH() - 22;
  String mm = "10 mm";
  if (bar > 260) { bar = k; x = width - 20 - bar; mm = "1 mm"; }
  noStroke(); fill(C_PANEL, 220); rect(x - 120, y - 26, bar + 128, 40, 6);
  stroke(C_TEXT); strokeWeight(2); line(x, y, x + bar, y); line(x, y - 4, x, y + 4); line(x + bar, y - 4, x + bar, y + 4);
  noStroke(); fill(C_TEXT); textSize(11); textAlign(CENTER, BOTTOM); text(mm, x + bar / 2, y - 4);
  fill(C_ACCENT); textAlign(LEFT, CENTER); textSize(12);
  text(round(viewZoom * 100) + "%", x - 112, y - 10);
  fill(C_DIM); textSize(10); text("double-click = fit", x - 112, y + 5);
}
