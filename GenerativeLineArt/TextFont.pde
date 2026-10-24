// Text pattern (34): single-line (Hershey) fonts, so letters are drawn with
// one pen stroke instead of an outline. The font files are in data/ (see
// data/HERSHEY_FONTS_NOTICE.txt). Each layer has its own text.

final String[] HERSHEY_NAMES = { "Sans", "Serif", "Script" };
final String[] HERSHEY_FILES = { "futural.jhf", "timesr.jhf", "scripts.jhf" };

class HGlyph {
  float left, right;
  ArrayList<float[]> strokes = new ArrayList<float[]>();   // x, y pairs in font units
}

HGlyph[][] hFonts = new HGlyph[HERSHEY_FILES.length][];

void loadHersheyFonts() {
  for (int f = 0; f < HERSHEY_FILES.length; f++) {
    String[] ls = null;
    try { ls = loadStrings(HERSHEY_FILES[f]); } catch (Exception e) {}
    if (ls == null) { println("Font missing: data/" + HERSHEY_FILES[f]); continue; }
    ArrayList<HGlyph> gs = new ArrayList<HGlyph>();
    for (int i = 0; i < ls.length; i++) {
      String rec = ls[i];
      if (rec.length() < 10) continue;
      int count;
      try { count = Integer.parseInt(rec.substring(5, 8).trim()); } catch (Exception e) { continue; }
      while (rec.length() < 8 + 2 * count && i + 1 < ls.length) rec += ls[++i];   // wrapped records
      HGlyph g = new HGlyph();
      g.left = rec.charAt(8) - 'R'; g.right = rec.charAt(9) - 'R';
      FloatList cur = new FloatList();
      for (int k = 10; k + 1 < min(rec.length(), 8 + 2 * count); k += 2) {
        if (rec.charAt(k) == ' ' && rec.charAt(k + 1) == 'R') {          // pen up
          if (cur.size() >= 4) g.strokes.add(cur.array());
          cur = new FloatList();
          continue;
        }
        cur.append(rec.charAt(k) - 'R'); cur.append(rec.charAt(k + 1) - 'R');
      }
      if (cur.size() >= 4) g.strokes.add(cur.array());
      gs.add(g);
    }
    hFonts[f] = gs.toArray(new HGlyph[0]);            // glyph i is ASCII 32 + i
  }
}

// Plain ASCII: accents are dropped (e -> e), curly quotes straightened.
String plotText(String s) {
  s = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD).replaceAll("\\p{M}", "");
  s = s.replace('‘', '\'').replace('’', '\'').replace('“', '"').replace('”', '"').replace('–', '-').replace('—', '-');
  StringBuilder sb = new StringBuilder();
  for (char c : s.toCharArray()) sb.append(c == '|' || (c >= 32 && c < 127) ? c : '?');
  return sb.toString();
}

HGlyph glyph(HGlyph[] font, char c) {
  int i = c - 32;
  return i >= 0 && i < font.length ? font[i] : font['?' - 32];
}

void genText(ArrayList<ArrayList<PVector>> out) {
  int fi = (int) pv(0), align = (int) pv(4), pos = (int) pv(5), weight = (int) pv(6);
  float size = pv(1), lsp = pv(2), track = pv(3);
  boolean fit = pv(7) > 0.5;
  HGlyph[] font = hFonts[fi];
  for (int f = 0; font == null && f < hFonts.length; f++) font = hFonts[f];
  if (font == null) return;
  String[] lines = split(plotText(gen.text.s), '|');

  // font units: capitals run from y = -12 to the baseline at y = 9
  float k = size / 21, pitch = size * lsp;
  float[] lw = new float[lines.length];
  float maxW = 1e-3;
  for (int i = 0; i < lines.length; i++) {
    for (char c : lines[i].toCharArray()) { HGlyph g = glyph(font, c); lw[i] += (g.right - g.left) * k + track; }
    if (lines[i].length() > 0) lw[i] -= track;
    maxW = max(maxW, lw[i]);
  }
  float aw = xmax - xmin, ah = ymax - ymin, blockH = (lines.length - 1) * pitch + size * 28 / 21;   // incl. descenders
  float f = fit ? min(aw / maxW, ah / blockH) * 0.98 : min(1, aw / maxW);   // never wider than the page
  k *= f; pitch *= f; track *= f; blockH *= f;
  for (int i = 0; i < lw.length; i++) lw[i] *= f;
  float capTop = pos == 0 ? ymin : (pos == 1 ? (ymin + ymax - blockH) / 2 : ymax - blockH);

  for (int i = 0; i < lines.length; i++) {
    float base = capTop + 21 * k + i * pitch;
    float x = align == 0 ? xmin : (align == 1 ? (xmin + xmax - lw[i]) / 2 : xmax - lw[i]);
    for (char c : lines[i].toCharArray()) {
      HGlyph g = glyph(font, c);
      for (int w = 0; w < weight; w++) {
        float a = w == 0 ? 0 : TWO_PI * (w - 1) / max(1, weight - 1);
        float ox = w == 0 ? 0 : 0.22 * cos(a), oy = w == 0 ? 0 : 0.22 * sin(a);   // extra passes for a bolder line
        for (float[] st : g.strokes) {
          ArrayList<PVector> pts = new ArrayList<PVector>(st.length / 2);
          for (int p = 0; p + 1 < st.length; p += 2) pts.add(new PVector(x + (st[p] - g.left) * k + ox, base + (st[p + 1] - 9) * k + oy));
          emit(out, pts);
        }
      }
      x += (g.right - g.left) * k + track;
    }
  }
}
