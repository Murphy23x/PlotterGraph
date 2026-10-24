// Patterns that draw external data: Route (30) and Data lines (31).
// The data itself is loaded on the Sources tab (see Sources).

// ----- 30: route (GPX / GeoJSON / OpenStreetMap) ------
void genRoute(ArrayList<ArrayList<PVector>> out) {
  int smooth = (int) pv(0), copies = (int) pv(1), frame = (int) pv(3);
  float off = pv(2);
  boolean fill = pv(4) > 0.5;
  ArrayList<double[]> lines = geoLines != null ? geoLines : demoRoute();

  // Web Mercator: x = lon, y = ln(tan(pi/4 + lat/2)), both in radians of the earth
  ArrayList<double[]> proj = new ArrayList<double[]>(lines.size());
  double x0 = Double.MAX_VALUE, y0 = Double.MAX_VALUE, x1 = -Double.MAX_VALUE, y1 = -Double.MAX_VALUE;
  for (double[] l : lines) {
    double[] p = new double[l.length];
    for (int i = 0; i + 1 < l.length; i += 2) {
      p[i] = Math.toRadians(l[i]);
      p[i + 1] = mercY(l[i + 1]);
      x0 = Math.min(x0, p[i]); x1 = Math.max(x1, p[i]); y0 = Math.min(y0, p[i + 1]); y1 = Math.max(y1, p[i + 1]);
    }
    proj.add(p);
  }
  if (geoFocus != null && geoLines != null) {        // a street fetch: frame the circle that was asked for
    double cx = Math.toRadians(geoFocus[1]), cy = mercY(geoFocus[0]);
    double r = geoFocus[2] / (6378137.0 * Math.cos(Math.toRadians(geoFocus[0])));
    x0 = cx - r; x1 = cx + r; y0 = cy - r; y1 = cy + r;
  }
  double bw = Math.max(x1 - x0, 1e-12), bh = Math.max(y1 - y0, 1e-12);

  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float tw = xmax - xmin, th = ymax - ymin;
  if (frame == 2) { tw = min(tw, th); th = tw; }
  double s = fill ? Math.max(tw / bw, th / bh) : Math.min(tw / bw, th / bh);
  double mx = (x0 + x1) / 2, my = (y0 + y1) / 2;

  ArrayList<ArrayList<PVector>> raw = new ArrayList<ArrayList<PVector>>();
  for (double[] p : proj) {
    ArrayList<PVector> pts = new ArrayList<PVector>(p.length / 2);
    for (int i = 0; i + 1 < p.length; i += 2) {
      PVector v = new PVector((float) (cx + (p[i] - mx) * s), (float) (cy - (p[i + 1] - my) * s));
      if (pts.isEmpty() || PVector.dist(pts.get(pts.size() - 1), v) > 0.02) pts.add(v);
    }
    if (pts.size() < 2) continue;
    if (smooth > 0) pts = chaikin(pts, smooth);
    for (int c = 0; c < copies; c++) {
      float d = (c - (copies - 1) / 2.0) * off;
      raw.add(d == 0 ? pts : offsetPath(pts, d));
    }
  }

  if (frame == 2) {
    float R = tw / 2;
    for (ArrayList<PVector> p : raw) clipCircle(p, cx, cy, R, out);
    emit(out, circlePath(cx, cy, R, 360));
  } else {
    for (ArrayList<PVector> p : raw) emit(out, p);
    if (frame == 1) {
      float i = 0.01;                                    // just inside, so emit() keeps it
      emit(out, rectPath(xmin + i, ymin + i, xmax - i, ymax - i));
    }
  }
}

double mercY(double latDeg) {
  double la = Math.toRadians(constrain((float) latDeg, -85, 85));
  return Math.log(Math.tan(Math.PI / 4 + la / 2));
}

// A meandering demo "walk" when no route is loaded (follows the seed).
ArrayList<double[]> demoRoute() {
  ArrayList<double[]> out = new ArrayList<double[]>();
  for (int k = 0; k < 2; k++) {
    DoubleList l = new DoubleList();
    double lon = 5.1 + k * 0.004, lat = 52.09;
    float a = random(TWO_PI);
    for (int i = 0; i < 700; i++) {
      a += (noise(i * 0.02, k * 10) - 0.5) * 0.5;
      lon += Math.cos(a) * 0.00006 / Math.cos(Math.toRadians(lat));
      lat += Math.sin(a) * 0.00006;
      l.append(lon); l.append(lat);
    }
    out.add(l.array());
  }
  return out;
}

// Parallel copy of a polyline, 'd' mm to its left (per-vertex averaged normals).
ArrayList<PVector> offsetPath(ArrayList<PVector> p, float d) {
  int n = p.size();
  ArrayList<PVector> r = new ArrayList<PVector>(n);
  for (int i = 0; i < n; i++) {
    PVector a = p.get(max(0, i - 1)), b = p.get(min(n - 1, i + 1));
    float dx = b.x - a.x, dy = b.y - a.y, l = sqrt(dx * dx + dy * dy);
    if (l < 1e-6) { r.add(p.get(i).copy()); continue; }
    r.add(new PVector(p.get(i).x - dy / l * d, p.get(i).y + dx / l * d));
  }
  return r;
}

// Keep the parts of a polyline inside a circle (exact segment intersection).
void clipCircle(ArrayList<PVector> pts, float cx, float cy, float R, ArrayList<ArrayList<PVector>> out) {
  ArrayList<PVector> cur = null;
  for (int i = 0; i + 1 < pts.size(); i++) {
    PVector a = pts.get(i), b = pts.get(i + 1);
    float dx = b.x - a.x, dy = b.y - a.y, fx = a.x - cx, fy = a.y - cy;
    float A = dx * dx + dy * dy, B = 2 * (fx * dx + fy * dy), C = fx * fx + fy * fy - R * R;
    float t0, t1;
    if (A < 1e-12) { if (C > 0) continue; t0 = 0; t1 = 1; }
    else {
      float disc = B * B - 4 * A * C;
      if (disc <= 0) { if (cur != null && cur.size() >= 2) out.add(cur); cur = null; continue; }
      float sq = sqrt(disc);
      t0 = max(0, (-B - sq) / (2 * A)); t1 = min(1, (-B + sq) / (2 * A));
    }
    if (t0 >= t1) { if (cur != null && cur.size() >= 2) out.add(cur); cur = null; continue; }
    PVector p0 = new PVector(a.x + dx * t0, a.y + dy * t0), p1 = new PVector(a.x + dx * t1, a.y + dy * t1);
    if (cur != null && t0 > 0) { if (cur.size() >= 2) out.add(cur); cur = null; }
    if (cur == null) { cur = new ArrayList<PVector>(); cur.add(p0); }
    cur.add(p1);
    if (t1 < 1) { if (cur.size() >= 2) out.add(cur); cur = null; }
  }
  if (cur != null && cur.size() >= 2) out.add(cur);
}

// ----- 31: data lines (CSV / JSON series) ------
void genDataLines(ArrayList<ArrayList<PVector>> out) {
  int style = (int) pv(0), rowLen = (int) pv(1), smooth = (int) pv(3), res = (int) pv(4);
  float amp = pv(2), inner = pv(5);
  boolean hide = pv(6) > 0.5, perRow = pv(7) > 0.5;
  ArrayList<float[]> src = dataSeries != null ? dataSeries : demoData();

  // rows: the series as they are, or each series cut into rows of 'rowLen'
  int rl = rowLen > 0 ? rowLen : (dataSeries != null ? dataRowHint : 0);
  if (rl == 0 && src.size() == 1 && src.get(0).length > 150) rl = ceil(src.get(0).length / 50.0);
  ArrayList<float[]> rows = new ArrayList<float[]>();
  if (rl > 0) {
    for (float[] s : src) for (int i = 0; i < s.length; i += rl) if (s.length - i >= 2) rows.add(subset(s, i, min(rl, s.length - i)));
  } else rows.addAll(src);
  if (rows.isEmpty()) return;

  float[][] v = new float[rows.size()][];
  float gmn = Float.MAX_VALUE, gmx = -Float.MAX_VALUE;
  for (int j = 0; j < v.length; j++) {
    float[] r = rows.get(j);
    v[j] = resample(movingAverage(r, min(smooth, (r.length - 1) / 8)), res + 1);   // short rows: less smoothing
    for (float x : v[j]) { gmn = min(gmn, x); gmx = max(gmx, x); }
  }
  for (float[] r : v) {
    float mn = gmn, mx = gmx;
    if (perRow) { mn = Float.MAX_VALUE; mx = -Float.MAX_VALUE; for (float x : r) { mn = min(mn, x); mx = max(mx, x); } }
    float d = max(mx - mn, 1e-9);
    for (int i = 0; i < r.length; i++) r[i] = (r[i] - mn) / d;
  }

  if (style == 0) { ridgelines(out, v, amp, hide); return; }
  float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2;
  float R = max(1, min(xmax - xmin, ymax - ymin) / 2 - amp), r0 = inner * R;
  int n = v.length;
  if (style == 1) {                                  // one ring per row, inside out
    for (int j = 0; j < n; j++) {
      float rj = n == 1 ? (r0 + R) / 2 : lerp(r0, R, j / (float) (n - 1));
      ArrayList<PVector> pts = new ArrayList<PVector>(res + 1);
      for (int i = 0; i <= res; i++) {
        float a = -HALF_PI + TWO_PI * i / (res + 1), r = rj + v[j][i] * amp;
        pts.add(new PVector(cx + cos(a) * r, cy + sin(a) * r));
      }
      emit(out, pts);
    }
  } else {                                           // one turn of a single spiral per row
    float step = (R - r0) / n;
    ArrayList<PVector> pts = new ArrayList<PVector>(n * res);
    for (int j = 0; j < n; j++) for (int i = 0; i < res; i++) {
      float t = j + i / (float) res, a = -HALF_PI + TWO_PI * t, r = r0 + step * t + v[j][i] * amp;
      pts.add(new PVector(cx + cos(a) * r, cy + sin(a) * r));
    }
    emit(out, pts);
  }
}

// Stacked lines, peaks pointing up; with 'hide' a line disappears behind the
// lines in front of (below) it, like the Wave lines pattern.
void ridgelines(ArrayList<ArrayList<PVector>> out, float[][] v, float amp, boolean hide) {
  int n = v.length;
  if (n == 0) return;
  int res = v[0].length - 1;
  float w = xmax - xmin, top = min(ymin + amp, ymax), bot = ymax;
  float[] sky = new float[res + 1];
  Arrays.fill(sky, Float.MAX_VALUE);
  for (int j = n - 1; j >= 0; j--) {
    float base = n == 1 ? (top + bot) / 2 : lerp(top, bot, j / (float) (n - 1));
    ArrayList<PVector> cur = null;
    for (int i = 0; i <= res; i++) {
      float x = xmin + w * i / res, y = base - v[j][min(i, v[j].length - 1)] * amp;
      if (!hide || y < sky[i]) {
        if (cur == null) cur = new ArrayList<PVector>();
        cur.add(new PVector(x, y));
      } else if (cur != null) { emit(out, cur); cur = null; }
      if (y < sky[i]) sky[i] = y;
    }
    if (cur != null) emit(out, cur);
  }
}

float[] movingAverage(float[] s, int r) {
  if (r <= 0 || s.length < 3) return s;
  float[] o = new float[s.length];
  for (int i = 0; i < s.length; i++) {
    float sum = 0; int c = 0;
    for (int k = max(0, i - r); k <= min(s.length - 1, i + r); k++) { sum += s[k]; c++; }
    o[i] = sum / c;
  }
  return o;
}

// Linear resampling to n points.
float[] resample(float[] s, int n) {
  float[] o = new float[n];
  if (s.length == 1) { Arrays.fill(o, s[0]); return o; }
  for (int i = 0; i < n; i++) {
    float t = i * (s.length - 1) / (float) max(1, n - 1);
    int k = min((int) t, s.length - 2);
    o[i] = lerp(s[k], s[k + 1], t - k);
  }
  return o;
}

// "Unknown Pleasures"-style demo rows (follow the seed).
ArrayList<float[]> demoData() {
  ArrayList<float[]> out = new ArrayList<float[]>();
  for (int j = 0; j < 45; j++) {
    float[] r = new float[120];
    float c1 = random(0.38, 0.62), c2 = random(0.38, 0.62), a1 = random(0.3, 1), a2 = random(0.2, 0.8);
    for (int i = 0; i < r.length; i++) {
      float u = i / 119.0;
      r[i] = a1 * exp(-sq((u - c1) / 0.06)) + a2 * exp(-sq((u - c2) / 0.04))
        + 0.25 * noise(i * 0.15, j * 0.5) * exp(-sq((u - 0.5) / 0.2)) + 0.05 * noise(i * 0.6, j);
    }
    out.add(r);
  }
  return out;
}
