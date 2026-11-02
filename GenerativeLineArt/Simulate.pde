// Plot simulation: plays the plot back in the order and at the speed the
// plotter will draw it (pen-down speed, travel speed and pen lifts from the
// Output tab), layer after layer. Travel moves show as a thin line behind
// the pen. Plays the whole plot in about 30 seconds by default.
//   G = start / stop, Space = pause, + / - = faster / slower,
//   click the time bar to jump, Esc = stop

boolean simOn = false, simPaused = false;
float simT = 0, simTotal = 0, simSpeed = 1;
int simLastMs = 0;
ArrayList<float[]> simEvents = new ArrayList<float[]>();     // per path: layer, path, t start, t down, t end
ArrayList<ArrayList<PVector>> simPathsList = new ArrayList<ArrayList<PVector>>();
ArrayList<float[]> simCum = new ArrayList<float[]>();        // cumulative length per point
int simDrawn = 0;                     // paths already in the buffer
PGraphics simPg;
float simK, simOx, simOy;

void toggleSimulation() {
  if (simOn) { simOn = false; return; }
  buildSimulation();
  if (simEvents.isEmpty()) { setStatus("Nothing to plot: enable a layer first"); return; }
  exploreOn = false;
  resetView();
  simOn = true; simPaused = false; simT = 0; simDrawn = 0; simPg = null;
  simSpeed = max(1, simTotal / 30.0);
  simLastMs = millis();
}

void buildSimulation() {
  simEvents.clear(); simPathsList.clear(); simCum.clear();
  float t = 0, px = 0, py = 0;
  float down = pSpeedDown.val, up = pSpeedUp.val, lift = pLiftTime.val;
  for (Layer L : layers) {
    if (!L.pEnabled.on()) continue;
    for (ArrayList<PVector> p : L.paths) {
      if (p.size() < 2) continue;
      PVector a = p.get(0);
      float t0 = t;
      t += dist(px, py, a.x, a.y) / up + lift;               // travel, pen down
      float tDown = t;
      float[] cum = new float[p.size()];
      for (int i = 1; i < p.size(); i++) cum[i] = cum[i - 1] + PVector.dist(p.get(i - 1), p.get(i));
      t += cum[p.size() - 1] / down + lift;                     // draw, pen up
      simEvents.add(new float[] { L.id, simPathsList.size(), t0, tDown, t, px, py });
      simPathsList.add(p);
      simCum.add(cum);
      PVector b = p.get(p.size() - 1);
      px = b.x; py = b.y;
    }
  }
  simTotal = t + dist(px, py, 0, 0) / up;                      // back to the origin
}

// Draws one simulation frame in the preview area.
void drawSimulation() {
  int now = millis();
  if (!simPaused) simT = min(simTotal, simT + (now - simLastMs) / 1000.0 * simSpeed);
  simLastMs = now;

  int pw = max(1, round(genW * fitScale())), ph = max(1, round(genH * fitScale()));
  simK = pw / genW;
  simOx = PANEL_W + (areaW() - pw) / 2.0;
  simOy = (areaH() - 40 - ph) / 2.0 + 4;
  if (simPg == null || simPg.width != pw || simPg.height != ph) {
    simPg = createGraphics(pw, ph, JAVA2D);
    simPg.beginDraw(); simPg.background(paperColor()); simPg.endDraw();
    simDrawn = 0;
  }
  // paths finished since the last frame go into the buffer
  int done = simDrawn;
  while (done < simEvents.size() && simEvents.get(done)[4] <= simT) done++;
  if (done < simDrawn) {                                       // jumped back: start over
    simPg.beginDraw(); simPg.background(paperColor()); simPg.endDraw();
    simDrawn = 0;
  }
  if (done > simDrawn) {
    simPg.beginDraw();
    simPg.noFill(); simPg.strokeJoin(ROUND); simPg.strokeCap(ROUND);
    for (int i = simDrawn; i < done; i++) simStroke(simPg, i, -1);
    simPg.endDraw();
    simDrawn = done;
  }
  noStroke(); fill(0, 90); rect(simOx + 5, simOy + 6, pw, ph);
  image(simPg, simOx, simOy);

  // the path being drawn now, the travel line and the pen
  float penX = 0, penY = 0;
  boolean penDown = false;
  int cur = simDrawn;
  if (cur < simEvents.size()) {
    float[] e = simEvents.get(cur);
    if (simT >= e[2]) {
      if (simT < e[3]) {                                       // travelling to the path
        PVector a = simPathsList.get(cur).get(0);
        float f = constrain((simT - e[2]) / max(1e-6, e[3] - e[2] - pLiftTime.val), 0, 1);
        penX = lerp(e[5], a.x, f); penY = lerp(e[6], a.y, f);
        stroke(220, 60, 60, 160); strokeWeight(1);
        line(simOx + e[5] * simK, simOy + e[6] * simK, simOx + penX * simK, simOy + penY * simK);
      } else {
        float drawn = (simT - e[3]) * pSpeedDown.val;
        pushMatrix(); translate(simOx, simOy);
        noFill(); strokeJoin(ROUND); strokeCap(ROUND);
        PVector p = simStroke(g, cur, drawn);
        popMatrix();
        penX = p.x; penY = p.y; penDown = true;
      }
    } else { penX = e[5]; penY = e[6]; }
  }
  Layer L = cur < simEvents.size() ? layers[(int) simEvents.get(cur)[0]] : null;
  float sx = simOx + penX * simK, sy = simOy + penY * simK;
  noFill(); stroke(L == null ? C_DIM : L.penColor()); strokeWeight(2);
  ellipse(sx, sy, penDown ? 9 : 15, penDown ? 9 : 15);
  if (!penDown) { stroke(C_DIM); strokeWeight(1); line(sx - 10, sy, sx + 10, sy); line(sx, sy - 10, sx, sy + 10); }

  drawSimBar(L, cur);
  if (simT >= simTotal && !simPaused) { simPaused = true; setStatus("Plot finished: " + fmtClock(simTotal)); }
}

// Strokes path i (up to 'upTo' mm of it, all of it when negative) on g.
// Returns the last point drawn.
PVector simStroke(PGraphics gr, int i, float upTo) {
  Layer L = layers[(int) simEvents.get(i)[0]];
  ArrayList<PVector> p = simPathsList.get(i);
  float[] cum = simCum.get(i);
  gr.stroke(L.penColor());
  gr.strokeWeight(max(0.8, L.pPen.val * simK));
  gr.beginShape();
  PVector last = p.get(0);
  for (int k = 0; k < p.size(); k++) {
    if (upTo >= 0 && cum[k] > upTo) {
      PVector a = p.get(k - 1), b = p.get(k);
      float f = (upTo - cum[k - 1]) / max(1e-6, cum[k] - cum[k - 1]);
      last = new PVector(lerp(a.x, b.x, f), lerp(a.y, b.y, f));
      gr.vertex(last.x * simK, last.y * simK);
      break;
    }
    last = p.get(k);
    gr.vertex(last.x * simK, last.y * simK);
  }
  gr.endShape();
  return last;
}

float[] simBarRect() { return new float[] { PANEL_W + 30, areaH() - 34, areaW() - 60, 8 }; }

void drawSimBar(Layer L, int cur) {
  float[] b = simBarRect();
  noStroke(); fill(C_TRACK); rect(b[0], b[1], b[2], b[3], 4);
  // layer segments in their pen colour
  float t0 = 0;
  for (int i = 0; i < simEvents.size(); i++) {
    boolean last = i == simEvents.size() - 1 || simEvents.get(i + 1)[0] != simEvents.get(i)[0];
    if (last) {
      float t1 = simEvents.get(i)[4];
      fill(layers[(int) simEvents.get(i)[0]].penColor(), 120);
      rect(b[0] + b[2] * t0 / simTotal, b[1] + b[3] - 2, b[2] * (t1 - t0) / simTotal, 2);
      t0 = t1;
    }
  }
  fill(C_ACCENT); rect(b[0], b[1], b[2] * simT / max(1e-6, simTotal), b[3] - 3, 4);
  fill(C_TEXT); textSize(12); textAlign(LEFT, BOTTOM);
  String where = L == null ? "done" : "layer " + (L.id + 1) + "  ·  path " + min(cur + 1, simEvents.size()) + " of " + simEvents.size();
  text(fmtClock(simT) + " / " + fmtClock(simTotal) + "   " + where, b[0], b[1] - 6);
  fill(C_DIM); textAlign(RIGHT, BOTTOM); textSize(11);
  text((simPaused ? "paused  ·  " : "") + (simSpeed < 10 ? nf(simSpeed, 0, 1) : str(round(simSpeed))) + "x  ·  Space = pause  ·  +/- = speed  ·  click bar = jump  ·  G / Esc = stop", b[0] + b[2], b[1] - 6);
}

String fmtClock(float s) {
  int t = round(s), h = t / 3600, m = (t / 60) % 60, sec = t % 60;
  return (h > 0 ? h + ":" + nf(m, 2) : str(m)) + ":" + nf(sec, 2);
}

boolean simPress() {
  if (!simOn || mouseX < PANEL_W) return false;
  float[] b = simBarRect();
  if (mouseY >= b[1] - 10 && mouseY <= b[1] + b[3] + 10) {
    simT = constrain((mouseX - b[0]) / b[2], 0, 1) * simTotal;
    simPaused = false;
  } else simPaused = !simPaused;                              // click the page = pause / play
  return true;
}

boolean simKey() {
  if (!simOn) return false;
  if (key == ESC || key == 'g' || key == 'G') { key = 0; simOn = false; return true; }
  if (key == ' ') { simPaused = !simPaused; if (simT >= simTotal) { simT = 0; simPaused = false; } return true; }
  if (key == '+' || key == '=') { simSpeed = min(simSpeed * 2, 100000); return true; }
  if (key == '-') { simSpeed = max(simSpeed / 2, 0.25); return true; }
  return true;
}
