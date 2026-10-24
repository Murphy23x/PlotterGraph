// SVG import (pattern 32): a small SVG reader that turns path, polyline,
// polygon, line, rect, circle and ellipse elements (with their transforms)
// into polylines, so they go through masks, clean-up and plotter export.
// Closed shapes can be filled with (cross-)hatching, using the even-odd rule.

class SvgShape {
  ArrayList<PVector> pts = new ArrayList<PVector>();
  boolean closed;
}

ArrayList<SvgShape> svgShapes;
float[] svgBox;                        // x, y, w, h of the drawing (viewBox), or null
String svgName = "", svgPath = "";

boolean loadSvgFile(File f) {
  ArrayList<SvgShape> shapes = new ArrayList<SvgShape>();
  float[] box = null;
  try {
    XML x = loadXML(f.getAbsolutePath());
    box = svgViewBox(x);
    svgWalk(x, new double[] { 1, 0, 0, 1, 0, 0 }, shapes, true);
  } catch (Exception e) { println("SVG error: " + e); }
  if (shapes.isEmpty()) { setStatus("No drawable paths in " + f.getName()); return false; }
  svgShapes = shapes; svgBox = box; svgName = f.getName(); svgPath = f.getAbsolutePath();
  sourceChanged(32);
  setStatus("SVG loaded: " + f.getName() + " (" + shapes.size() + " paths)");
  return true;
}

void genSvg(ArrayList<ArrayList<PVector>> out) {
  boolean outline = pv(0) > 0.5, cross = pv(3) > 0.5;
  float hatch = pv(1), ang = radians(pv(2));
  ArrayList<SvgShape> shapes = svgShapes;
  float[] box = svgBox;
  if (shapes == null) {
    shapes = new ArrayList<SvgShape>();
    XML x = parseXML(DEMO_SVG);
    box = svgViewBox(x);
    svgWalk(x, new double[] { 1, 0, 0, 1, 0, 0 }, shapes, true);
  }
  if (box == null) {
    float x0 = Float.MAX_VALUE, y0 = Float.MAX_VALUE, x1 = -Float.MAX_VALUE, y1 = -Float.MAX_VALUE;
    for (SvgShape s : shapes) for (PVector v : s.pts) { x0 = min(x0, v.x); y0 = min(y0, v.y); x1 = max(x1, v.x); y1 = max(y1, v.y); }
    box = new float[] { x0, y0, max(x1 - x0, 1e-6), max(y1 - y0, 1e-6) };
  }
  float aw = xmax - xmin, ah = ymax - ymin, s = min(aw / box[2], ah / box[3]);
  float ox = xmin + (aw - box[2] * s) / 2 - box[0] * s, oy = ymin + (ah - box[3] * s) / 2 - box[1] * s;

  ArrayList<ArrayList<PVector>> polys = new ArrayList<ArrayList<PVector>>();
  for (SvgShape sh : shapes) {
    ArrayList<PVector> p = new ArrayList<PVector>(sh.pts.size() + 1);
    for (PVector v : sh.pts) p.add(new PVector(ox + v.x * s, oy + v.y * s));
    if (sh.closed && p.size() > 2) {
      polys.add(p);
      if (PVector.dist(p.get(0), p.get(p.size() - 1)) > 1e-4) { p = new ArrayList<PVector>(p); p.add(p.get(0).copy()); }
    }
    if (outline) emit(out, p);
  }
  if (hatch > 0) {
    hatchPolys(polys, hatch, ang, out);
    if (cross) hatchPolys(polys, hatch, ang + HALF_PI, out);
  }
}

// Even-odd scanline hatching of a set of polygons at angle 'ang'.
void hatchPolys(ArrayList<ArrayList<PVector>> polys, float sp, float ang, ArrayList<ArrayList<PVector>> out) {
  if (polys.isEmpty()) return;
  float c = cos(ang), s = sin(ang);
  ArrayList<float[]> rp = new ArrayList<float[]>();   // rotated by -ang: hatch lines become horizontal
  float y0 = Float.MAX_VALUE, y1 = -Float.MAX_VALUE;
  for (ArrayList<PVector> p : polys) {
    float[] r = new float[p.size() * 2];
    for (int i = 0; i < p.size(); i++) {
      PVector v = p.get(i);
      r[2 * i] = v.x * c + v.y * s; r[2 * i + 1] = -v.x * s + v.y * c;
      y0 = min(y0, r[2 * i + 1]); y1 = max(y1, r[2 * i + 1]);
    }
    rp.add(r);
  }
  int line = 0;
  for (float y = y0 + sp / 2; y < y1; y += sp, line++) {
    FloatList xs = new FloatList();
    for (float[] r : rp) {
      int n = r.length / 2;
      for (int i = 0; i < n; i++) {
        float ax = r[2 * i], ay = r[2 * i + 1], bx = r[2 * ((i + 1) % n)], by = r[2 * ((i + 1) % n) + 1];
        if ((ay <= y) != (by <= y)) xs.append(ax + (y - ay) * (bx - ax) / (by - ay));
      }
    }
    xs.sort();
    for (int k = 0; k + 1 < xs.size(); k += 2) {
      float xa = xs.get(k), xb = xs.get(k + 1);
      if (line % 2 == 1) { float t = xa; xa = xb; xb = t; }   // serpentine order
      ArrayList<PVector> seg = new ArrayList<PVector>(2);
      seg.add(new PVector(xa * c - y * s, xa * s + y * c));
      seg.add(new PVector(xb * c - y * s, xb * s + y * c));
      emit(out, seg);
    }
  }
}

final String DEMO_SVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 200\">"
  + "<circle cx=\"100\" cy=\"100\" r=\"92\"/>"
  + "<path d=\"M100 18 L121 74 L181 76 L134 113 L150 171 L100 138 L50 171 L66 113 L19 76 L79 74 Z\"/>"
  + "<g transform=\"translate(100 104) scale(0.32) translate(-100 -110)\">"
  + "<path d=\"M100 175 C40 130 20 95 45 65 A30 30 0 0 1 100 70 A30 30 0 0 1 155 65 C180 95 160 130 100 175 Z\"/></g>"
  + "</svg>";

float[] svgViewBox(XML root) {
  String vb = root.getString("viewBox");
  if (vb != null) {
    float[] v = float(splitTokens(vb, " ,\t\n"));
    if (v.length == 4 && v[2] > 0 && v[3] > 0) return v;
  }
  float w = svgLen(root.getString("width")), h = svgLen(root.getString("height"));
  if (w > 0 && h > 0 && root.getString("width").indexOf('%') < 0) return new float[] { 0, 0, w, h };
  return null;
}

// Leading number of an attribute such as "12.5px" (units are ignored).
float svgLen(String s) {
  if (s == null) return Float.NaN;
  String[] m = match(s.trim(), "^[-+]?(\\d*\\.\\d+|\\d+\\.?)([eE][-+]?\\d+)?");
  return m == null ? Float.NaN : Float.parseFloat(m[0]);
}

float svgAttr(XML e, String name, float def) {
  float v = svgLen(e.getString(name));
  return Float.isNaN(v) ? def : v;
}

final List<String> SVG_SKIP = Arrays.asList("defs", "clipPath", "mask", "symbol", "marker", "pattern", "metadata",
  "title", "desc", "style", "script", "text", "linearGradient", "radialGradient", "filter", "namedview");

void svgWalk(XML e, double[] m, ArrayList<SvgShape> out, boolean root) {
  String name = localName(e);
  if (name.startsWith("#") || SVG_SKIP.contains(name)) return;
  String style = e.getString("style", "");
  if ("none".equals(e.getString("display")) || "hidden".equals(e.getString("visibility")) || style.replace(" ", "").contains("display:none")) return;
  double[] mm = matMul(m, parseTransform(e.getString("transform")));
  ArrayList<SvgShape> loc = new ArrayList<SvgShape>();
  if (name.equals("path")) svgPathD(e.getString("d", ""), loc);
  else if (name.equals("rect")) {
    float x = svgAttr(e, "x", 0), y = svgAttr(e, "y", 0), w = svgAttr(e, "width", 0), h = svgAttr(e, "height", 0);
    if (w > 0 && h > 0) loc.add(shapeOf(new float[] { x, y, x + w, y, x + w, y + h, x, y + h }, true));
  } else if (name.equals("circle") || name.equals("ellipse")) {
    float cx = svgAttr(e, "cx", 0), cy = svgAttr(e, "cy", 0);
    float rx = name.equals("circle") ? svgAttr(e, "r", 0) : svgAttr(e, "rx", 0), ry = name.equals("circle") ? rx : svgAttr(e, "ry", 0);
    if (rx > 0 && ry > 0) {
      SvgShape s = new SvgShape(); s.closed = true;
      for (int i = 0; i < 96; i++) s.pts.add(new PVector(cx + rx * cos(TWO_PI * i / 96), cy + ry * sin(TWO_PI * i / 96)));
      loc.add(s);
    }
  } else if (name.equals("line")) {
    loc.add(shapeOf(new float[] { svgAttr(e, "x1", 0), svgAttr(e, "y1", 0), svgAttr(e, "x2", 0), svgAttr(e, "y2", 0) }, false));
  } else if (name.equals("polyline") || name.equals("polygon")) {
    float[] v = float(splitTokens(e.getString("points", ""), " ,\t\n\r"));
    if (v.length >= 4) loc.add(shapeOf(v.length % 2 == 0 ? v : subset(v, 0, v.length - 1), name.equals("polygon")));
  } else if (root || name.equals("svg") || name.equals("g") || name.equals("a") || name.equals("switch")) {
    for (XML c : e.getChildren()) svgWalk(c, mm, out, false);
  }
  for (SvgShape s : loc) {
    if (s.pts.size() < 2) continue;
    for (PVector v : s.pts) {
      float x = v.x, y = v.y;
      v.x = (float) (mm[0] * x + mm[2] * y + mm[4]);
      v.y = (float) (mm[1] * x + mm[3] * y + mm[5]);
    }
    out.add(s);
  }
}

SvgShape shapeOf(float[] xy, boolean closed) {
  SvgShape s = new SvgShape();
  s.closed = closed;
  for (int i = 0; i + 1 < xy.length; i += 2) s.pts.add(new PVector(xy[i], xy[i + 1]));
  return s;
}

// Affine matrices as { a, b, c, d, e, f }: x' = a x + c y + e, y' = b x + d y + f.
double[] matMul(double[] m, double[] n) {
  return new double[] {
    m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
    m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5] };
}

double[] parseTransform(String t) {
  double[] m = { 1, 0, 0, 1, 0, 0 };
  if (t == null) return m;
  String[][] all = matchAll(t, "([a-zA-Z]+)\\s*\\(([^)]*)\\)");
  if (all == null) return m;
  for (String[] g : all) {
    float[] a = float(splitTokens(g[2], " ,\t\n\r"));
    String f = g[1];
    double[] n = null;
    if (f.equals("matrix") && a.length == 6) n = new double[] { a[0], a[1], a[2], a[3], a[4], a[5] };
    else if (f.equals("translate") && a.length >= 1) n = new double[] { 1, 0, 0, 1, a[0], a.length > 1 ? a[1] : 0 };
    else if (f.equals("scale") && a.length >= 1) n = new double[] { a[0], 0, 0, a.length > 1 ? a[1] : a[0], 0, 0 };
    else if (f.equals("rotate") && a.length >= 1) {
      double r = Math.toRadians(a[0]), c = Math.cos(r), s = Math.sin(r);
      n = new double[] { c, s, -s, c, 0, 0 };
      if (a.length >= 3) n = matMul(matMul(new double[] { 1, 0, 0, 1, a[1], a[2] }, n), new double[] { 1, 0, 0, 1, -a[1], -a[2] });
    } else if (f.equals("skewX") && a.length >= 1) n = new double[] { 1, 0, Math.tan(Math.toRadians(a[0])), 1, 0, 0 };
    else if (f.equals("skewY") && a.length >= 1) n = new double[] { 1, Math.tan(Math.toRadians(a[0])), 0, 1, 0, 0 };
    if (n != null) m = matMul(m, n);
  }
  return m;
}

// ----- path data ("d" attribute) -----
class PathTok {
  String s; int i = 0;
  PathTok(String s) { this.s = s; }
  void skip() { while (i < s.length() && (Character.isWhitespace(s.charAt(i)) || s.charAt(i) == ',')) i++; }
  boolean atNumber() {
    skip();
    if (i >= s.length()) return false;
    char c = s.charAt(i);
    return (c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.';
  }
  float num() {
    skip();
    int st = i;
    if (i < s.length() && (s.charAt(i) == '-' || s.charAt(i) == '+')) i++;
    boolean dot = false;
    while (i < s.length()) {
      char c = s.charAt(i);
      if (c >= '0' && c <= '9') i++;
      else if (c == '.' && !dot) { dot = true; i++; }
      else break;
    }
    if (i < s.length() && (s.charAt(i) == 'e' || s.charAt(i) == 'E')) {
      int save = i; i++;
      if (i < s.length() && (s.charAt(i) == '-' || s.charAt(i) == '+')) i++;
      if (i < s.length() && Character.isDigit(s.charAt(i))) { while (i < s.length() && Character.isDigit(s.charAt(i))) i++; }
      else i = save;
    }
    if (st == i) { i++; return 0; }                 // garbage: skip a character
    return Float.parseFloat(s.substring(st, i));
  }
  float flag() {                                       // arc flags may be written without separators
    skip();
    if (i < s.length() && (s.charAt(i) == '0' || s.charAt(i) == '1')) return s.charAt(i++) - '0';
    return num();
  }
}

void svgPathD(String d, ArrayList<SvgShape> out) {
  PathTok t = new PathTok(d);
  float cx = 0, cy = 0, sx = 0, sy = 0, lcx = 0, lcy = 0;   // current, subpath start, last control point
  char cmd = ' ', prev = ' ';
  SvgShape cur = null;
  while (true) {
    t.skip();
    if (t.i >= t.s.length()) break;
    char ch = t.s.charAt(t.i);
    if (Character.isLetter(ch) && ch != 'e' && ch != 'E') { cmd = ch; t.i++; }
    else if (cmd == ' ') { t.i++; continue; }
    else if (cmd == 'M') cmd = 'L';                      // extra pairs after a move are lines
    else if (cmd == 'm') cmd = 'l';
    boolean rel = Character.isLowerCase(cmd);
    char C = Character.toUpperCase(cmd);
    if (C == 'Z') {
      if (cur != null) { cur.closed = true; if (cur.pts.size() > 1) out.add(cur); cur = null; }
      cx = sx; cy = sy;
      prev = 'Z';
      continue;
    }
    if (!t.atNumber()) { t.i++; continue; }
    if (C == 'M') {
      float x = t.num(), y = t.num();
      if (rel) { x += cx; y += cy; }
      if (cur != null && cur.pts.size() > 1) out.add(cur);
      cur = new SvgShape(); cur.pts.add(new PVector(x, y));
      cx = sx = x; cy = sy = y;
    } else {
      if (cur == null) { cur = new SvgShape(); cur.pts.add(new PVector(cx, cy)); sx = cx; sy = cy; }
      if (C == 'L' || C == 'H' || C == 'V') {
        float x = cx, y = cy;
        if (C == 'L') { x = t.num(); y = t.num(); if (rel) { x += cx; y += cy; } }
        else if (C == 'H') { x = t.num() + (rel ? cx : 0); }
        else { y = t.num() + (rel ? cy : 0); }
        cur.pts.add(new PVector(x, y));
        cx = x; cy = y;
      } else if (C == 'C' || C == 'S') {
        float x1, y1;
        if (C == 'C') { x1 = t.num(); y1 = t.num(); if (rel) { x1 += cx; y1 += cy; } }
        else if ("CcSs".indexOf(prev) >= 0) { x1 = 2 * cx - lcx; y1 = 2 * cy - lcy; }
        else { x1 = cx; y1 = cy; }
        float x2 = t.num(), y2 = t.num(), x = t.num(), y = t.num();
        if (rel) { x2 += cx; y2 += cy; x += cx; y += cy; }
        for (int k = 1; k <= 20; k++) {
          float u = k / 20.0, a = (1 - u) * (1 - u) * (1 - u), b = 3 * u * (1 - u) * (1 - u), c = 3 * u * u * (1 - u), e = u * u * u;
          cur.pts.add(new PVector(a * cx + b * x1 + c * x2 + e * x, a * cy + b * y1 + c * y2 + e * y));
        }
        lcx = x2; lcy = y2; cx = x; cy = y;
      } else if (C == 'Q' || C == 'T') {
        float x1, y1;
        if (C == 'Q') { x1 = t.num(); y1 = t.num(); if (rel) { x1 += cx; y1 += cy; } }
        else if ("QqTt".indexOf(prev) >= 0) { x1 = 2 * cx - lcx; y1 = 2 * cy - lcy; }
        else { x1 = cx; y1 = cy; }
        float x = t.num(), y = t.num();
        if (rel) { x += cx; y += cy; }
        for (int k = 1; k <= 14; k++) {
          float u = k / 14.0, a = (1 - u) * (1 - u), b = 2 * u * (1 - u), c = u * u;
          cur.pts.add(new PVector(a * cx + b * x1 + c * x, a * cy + b * y1 + c * y));
        }
        lcx = x1; lcy = y1; cx = x; cy = y;
      } else if (C == 'A') {
        float rx = abs(t.num()), ry = abs(t.num()), rot = t.num(), large = t.flag(), sweep = t.flag();
        float x = t.num(), y = t.num();
        if (rel) { x += cx; y += cy; }
        svgArc(cur.pts, cx, cy, rx, ry, rot, large > 0.5, sweep > 0.5, x, y);
        cx = x; cy = y;
      } else { t.i++; continue; }
    }
    prev = cmd;
  }
  if (cur != null && cur.pts.size() > 1) out.add(cur);
}

// Endpoint arc -> centre parametrisation (SVG spec, appendix F.6.5).
void svgArc(ArrayList<PVector> pts, float x1, float y1, float rx, float ry, float rotDeg, boolean large, boolean sweep, float x2, float y2) {
  if (rx < 1e-6 || ry < 1e-6) { pts.add(new PVector(x2, y2)); return; }
  double phi = Math.toRadians(rotDeg), cp = Math.cos(phi), sp = Math.sin(phi);
  double dx = (x1 - x2) / 2.0, dy = (y1 - y2) / 2.0;
  double xp = cp * dx + sp * dy, yp = -sp * dx + cp * dy;
  double lam = xp * xp / (rx * rx) + yp * yp / (ry * ry);
  double Rx = rx, Ry = ry;
  if (lam > 1) { Rx *= Math.sqrt(lam); Ry *= Math.sqrt(lam); }
  double num = Rx * Rx * Ry * Ry - Rx * Rx * yp * yp - Ry * Ry * xp * xp, den = Rx * Rx * yp * yp + Ry * Ry * xp * xp;
  double co = den == 0 ? 0 : Math.sqrt(Math.max(0, num / den)) * (large == sweep ? -1 : 1);
  double cxp = co * Rx * yp / Ry, cyp = -co * Ry * xp / Rx;
  double ccx = cp * cxp - sp * cyp + (x1 + x2) / 2.0, ccy = sp * cxp + cp * cyp + (y1 + y2) / 2.0;
  double th1 = Math.atan2((yp - cyp) / Ry, (xp - cxp) / Rx);
  double dth = Math.atan2((-yp - cyp) / Ry, (-xp - cxp) / Rx) - th1;
  if (sweep && dth < 0) dth += 2 * Math.PI;
  if (!sweep && dth > 0) dth -= 2 * Math.PI;
  int n = max(2, (int) Math.ceil(Math.abs(dth) / Math.toRadians(5)));
  for (int k = 1; k <= n; k++) {
    double a = th1 + dth * k / n;
    pts.add(new PVector((float) (ccx + Rx * Math.cos(a) * cp - Ry * Math.sin(a) * sp), (float) (ccy + Rx * Math.cos(a) * sp + Ry * Math.sin(a) * cp)));
  }
}
