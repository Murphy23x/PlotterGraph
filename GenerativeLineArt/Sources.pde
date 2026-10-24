// External sources: everything that brings outside data into a design.
// ------------------------------------------------------------------
// * web: download with a local cache (GenerativeLineArt/cache), so a preset
//   that used a URL keeps working offline and keeps giving the same design
// * location: place name or "lat, lon" -> OpenStreetMap streets (Overpass),
//   terrain (Terrarium elevation tiles) and weather (Open-Meteo)
// * files: GPX / GeoJSON routes, CSV / JSON data series, field grids
//   (CSV matrix, ESRI .asc, grey-scale heightmap), plus SVG, audio and text
//   (see the SvgImport / Audio / TextFont tabs)
// * field sources: Flow field, Wave lines, Contour map and Hatch shading can
//   read a photo or a grid instead of noise
// * watch folder: new files dropped into a folder are loaded (and exported)
// * text -> design: a name or phrase always gives the same seed / design
//
// Network work runs on a background thread; results are applied on the
// animation thread through runMainQueue().

import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URLEncoder;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.ByteArrayOutputStream;
import java.security.MessageDigest;

final String USER_AGENT = "PlotterGraph/2.0 (+https://github.com/Murphy23x/PlotterGraph)";
final String[] STREET_TYPES = { "All roads", "Major roads", "Water", "Buildings" };

TextVal tvLocation = new TextVal("Utrecht", 120);
TextVal tvUrl      = new TextVal("", 600);
TextVal tvSeedText = new TextVal("", 120);
TextVal tvPrompt   = new TextVal("", 400);

File pendingAutoExport;

// ---------- background jobs ------------------------------------------------
interface Task { void run() throws Exception; }

final ArrayList<Runnable> mainQueue = new ArrayList<Runnable>();
volatile int busyCount = 0;
volatile String busyWhat = "";
boolean syncJobs = false;              // command-line mode: run everything inline

void onMain(Runnable r) {
  if (syncJobs) { r.run(); return; }
  synchronized (mainQueue) { mainQueue.add(r); }
}

void runMainQueue() {
  ArrayList<Runnable> todo;
  synchronized (mainQueue) { todo = new ArrayList<Runnable>(mainQueue); mainQueue.clear(); }
  for (Runnable r : todo) r.run();
}

// Runs 'work' off the animation thread; errors end up in the status bar.
void runAsync(final String what, final Task work) {
  if (syncJobs) {
    try { work.run(); } catch (Exception e) { cliError(what + " failed: " + errText(e)); }
    return;
  }
  busyCount++;
  busyWhat = what + "...";
  new Thread(new Runnable() {
    public void run() {
      try { work.run(); }
      catch (Exception e) {
        final String msg = what + " failed: " + errText(e);
        println(msg);
        onMain(new Runnable() { public void run() { setStatus(msg); } });
      }
      finally { onMain(new Runnable() { public void run() { busyCount = max(0, busyCount - 1); } }); }
    }
  }).start();
}

String errText(Exception e) {
  String m = e.getMessage();
  return m == null || m.isEmpty() ? e.getClass().getSimpleName() : m;
}

void statusAsync(final String s) {              // setStatus from any thread
  onMain(new Runnable() { public void run() { setStatus(s); } });
  if (syncJobs) println(s);
}

// ---------- HTTP + cache ---------------------------------------------------
byte[] readAllBytes(InputStream in) throws Exception {
  if (in == null) return new byte[0];
  ByteArrayOutputStream bo = new ByteArrayOutputStream();
  byte[] buf = new byte[1 << 16];
  int n;
  try { while ((n = in.read(buf)) > 0) bo.write(buf, 0, n); } finally { in.close(); }
  return bo.toByteArray();
}

// GET (body == null) or POST. Follows redirects (also http -> https), but never
// https -> http, and a request with headers or a body only within the same host.
byte[] httpRequest(String url, String body, String[] headers) throws Exception {
  for (int hop = 0; hop < 5; hop++) {
    HttpURLConnection c = (HttpURLConnection) URI.create(url).toURL().openConnection();
    c.setConnectTimeout(20000);
    c.setReadTimeout(180000);
    c.setInstanceFollowRedirects(false);
    c.setRequestProperty("User-Agent", USER_AGENT);
    if (headers != null) for (int i = 0; i + 1 < headers.length; i += 2) c.setRequestProperty(headers[i], headers[i + 1]);
    if (body != null) {
      c.setRequestMethod("POST");
      c.setDoOutput(true);
      OutputStream os = c.getOutputStream();
      os.write(body.getBytes("UTF-8"));
      os.close();
    }
    int code = c.getResponseCode();
    if (code >= 300 && code < 400 && c.getHeaderField("Location") != null) {
      URI cur = URI.create(url), next = cur.resolve(c.getHeaderField("Location"));
      if ("https".equalsIgnoreCase(cur.getScheme()) && !"https".equalsIgnoreCase(next.getScheme()))
        throw new Exception("refused a redirect from https to " + next.getScheme());
      // headers (an API key) and a body are never sent on to another host
      if ((headers != null || body != null) && !sameOrigin(cur, next))
        throw new Exception("refused a redirect to another host (" + next.getHost() + ")");
      url = next.toString();
      continue;
    }
    byte[] b = readAllBytes(code >= 400 ? c.getErrorStream() : c.getInputStream());
    if (code >= 400) {
      String t = new String(b, "UTF-8").trim();
      if (t.startsWith("<")) t = "";                    // an HTML error page says nothing useful here
      if (t.length() > 300) t = t.substring(0, 300) + "...";
      throw new Exception("HTTP " + code + " from " + URI.create(url).getHost() + (t.isEmpty() ? "" : ": " + t));
    }
    return b;
  }
  throw new Exception("too many redirects");
}

boolean sameOrigin(URI a, URI b) {
  return a.getScheme() != null && a.getScheme().equalsIgnoreCase(b.getScheme())
    && a.getHost() != null && a.getHost().equalsIgnoreCase(b.getHost()) && port(a) == port(b);
}

int port(URI u) { return u.getPort() >= 0 ? u.getPort() : ("https".equalsIgnoreCase(u.getScheme()) ? 443 : 80); }

String sha1(String s) {
  try {
    byte[] d = MessageDigest.getInstance("SHA-1").digest(s.getBytes("UTF-8"));
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < 8; i++) sb.append(String.format("%02x", d[i] & 255));
    return sb.toString();
  } catch (Exception e) { return hex(s.hashCode(), 8); }
}

File cacheDir() { File d = new File(sketchPath("cache")); d.mkdirs(); return d; }

// Downloads 'url' into the cache (once per 'key') and returns the file. The
// extension comes from the URL or, failing that, from the content.
File download(String url, String key) throws Exception {
  String h = sha1(key);
  File[] old = cacheDir().listFiles();
  if (old != null) for (File f : old) if (f.getName().startsWith(h + ".") && f.length() > 0) return f;
  byte[] b = httpRequest(url, null, null);
  if (b.length == 0) throw new Exception("empty response");
  String ext = extOf(URI.create(url).getPath());
  if (!KNOWN_EXT.contains(ext)) ext = sniffExt(b);
  File f = new File(cacheDir(), h + "." + ext);
  saveBytes(f.getAbsolutePath(), b);
  return f;
}

File download(String url) throws Exception { return download(url, url); }

final List<String> KNOWN_EXT = Arrays.asList("png", "jpg", "jpeg", "gif", "tga", "svg", "gpx", "geojson", "json",
  "csv", "tsv", "txt", "asc", "wav", "aif", "aiff", "au");

String extOf(String name) {
  if (name == null) return "";
  int i = name.lastIndexOf('.'), j = max(name.lastIndexOf('/'), name.lastIndexOf('\\'));
  return i > j && i >= 0 ? name.substring(i + 1).toLowerCase() : "";
}

// File type from the first bytes.
String sniffExt(byte[] b) {
  if (b.length > 4 && (b[0] & 255) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') return "png";
  if (b.length > 3 && (b[0] & 255) == 0xFF && (b[1] & 255) == 0xD8) return "jpg";
  if (b.length > 4 && b[0] == 'G' && b[1] == 'I' && b[2] == 'F') return "gif";
  if (b.length > 12 && b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F' && b[8] == 'W' && b[9] == 'A') return "wav";
  if (b.length > 12 && b[0] == 'F' && b[1] == 'O' && b[2] == 'R' && b[3] == 'M') return "aif";
  String head;
  try { head = new String(b, 0, min(b.length, 2000), "UTF-8").trim().toLowerCase(); } catch (Exception e) { head = ""; }
  if (head.startsWith("﻿")) head = head.substring(1).trim();
  if (head.startsWith("<")) {
    if (head.contains("<svg")) return "svg";
    if (head.contains("<gpx")) return "gpx";
    return "txt";
  }
  if (head.startsWith("{") || head.startsWith("[")) return "json";
  if (head.startsWith("ncols")) return "asc";
  return "csv";
}

// ---------- loading anything -------------------------------------------------
// Loads a file by its type. With 'pick' a layer is switched to the pattern
// that uses it, unless an enabled layer already does.
boolean loadAny(File f, boolean pick) {
  String ext = extOf(f.getName());
  boolean ok;
  if (Arrays.asList("png", "jpg", "jpeg", "gif", "tga").contains(ext)) {
    loadPhoto(f);
    ok = photo != null && photoPath.equals(f.getAbsolutePath());
    if (ok && pick && !anyLayer(26, -1) && !anyLayer(-1, 1)) useMode(26);
  } else if (ext.equals("svg")) {
    ok = loadSvgFile(f);
    if (ok && pick) pickMode(32);
  } else if (ext.equals("gpx") || ext.equals("geojson")) {
    ok = loadGeoFile(f);
    if (ok && pick) pickMode(30);
  } else if (ext.equals("asc") || f.getName().toLowerCase().matches(".*\\.grid\\.(csv|txt)$")) {
    ok = loadGridFile(f);
    if (ok && pick) pickGrid();
  } else if (Arrays.asList("wav", "aif", "aiff", "au").contains(ext)) {
    ok = loadAudioFile(f);
    if (ok && pick) pickMode(33);
  } else if (ext.equals("txt")) {
    String[] ls = loadStrings(f.getAbsolutePath());
    ok = ls != null;
    if (ok) {
      String t = join(ls, "|").trim();
      if (pick && !anyLayer(34, -1)) useMode(34);
      for (Layer L : layers) if (L.pMode.i() == 34) L.text.set(t);
      setStatus("Text loaded: " + f.getName());
    }
  } else if (ext.equals("json")) {
    JSONObject o = null;
    try { o = loadJSONObject(f.getAbsolutePath()); } catch (Exception e) {}
    if (o != null && o.hasKey("layers")) { ok = applyPreset(o); if (ok) setStatus("Preset loaded: " + f.getName()); }
    else if (o != null && (o.hasKey("elements") || isGeoJSON(o))) { ok = loadGeoFile(f); if (ok && pick) pickMode(30); }
    else { ok = loadDataFile(f); if (ok && pick) pickMode(31); }
  } else {                                           // csv, tsv and anything else: data series
    ok = loadDataFile(f);
    if (ok && pick) pickMode(31);
  }
  return ok;
}

boolean anyLayer(int mode, int field) {
  for (Layer L : layers) {
    if (!L.pEnabled.on()) continue;
    if (mode >= 0 && L.pMode.i() == mode) return true;
    if (field >= 0 && usesField(L.pMode.i()) && L.pField.i() == field) return true;
  }
  return false;
}

// The current layer switches to 'mode', unless it already draws another
// source: then the first unused layer is taken, so sources add up.
void useMode(int mode) {
  Layer L = layers[curLayer];
  if (L.pEnabled.on() && isSourceMode(L.pMode.i()) && L.pMode.i() != mode) {
    for (Layer o : layers) if (!o.pEnabled.on()) { L = o; break; }
  }
  L.pMode.set(mode);
  L.pEnabled.set(1);
}

boolean isSourceMode(int m) { return m == 26 || m >= 30; }

void pickMode(int mode) { if (!anyLayer(mode, -1)) useMode(mode); }

void pickGrid() {
  if (anyLayer(-1, 2)) return;
  Layer L = layers[curLayer];
  if (!usesField(L.pMode.i())) L.pMode.set(5);
  L.pField.set(2);
  L.pEnabled.set(1);
}

// Marks the layers that draw 'mode' for regeneration.
void sourceChanged(int mode) {
  for (Layer L : layers) if (L.pMode.i() == mode) L.dirty = true;
}

void fetchUrl(final String url0) {
  final String url = url0.trim();
  if (url.isEmpty()) { setStatus("Type or paste a web address first (Ctrl+V)"); return; }
  if (!url.matches("(?i)https?://.+")) { setStatus("The address must start with http:// or https://"); return; }
  runAsync("Downloading", new Task() {
    public void run() throws Exception {
      final File f = download(url);
      onMain(new Runnable() { public void run() {
        if (loadAny(f, true)) lastUrl = url;
      } });
    }
  });
}
String lastUrl = "";

// ---------- location -------------------------------------------------------
double locLat = Double.NaN, locLon = Double.NaN;
String locKey = "", locLabel = "";

// Turns the location field into coordinates (geocoding names with
// OpenStreetMap Nominatim). Blocking: call from a background task.
double[] resolveLocation() throws Exception {
  String q = tvLocation.s.trim();
  if (q.isEmpty()) throw new Exception("type a place or \"lat, lon\" in the location field");
  if (q.equals(locKey) && !Double.isNaN(locLat)) return new double[] { locLat, locLon };
  String[] m = match(q, "^\\s*(-?\\d+(?:\\.\\d+)?)\\s*[,; ]\\s*(-?\\d+(?:\\.\\d+)?)\\s*$");
  double lat, lon;
  String label;
  if (m != null) {
    lat = Double.parseDouble(m[1]); lon = Double.parseDouble(m[2]);
    label = String.format(Locale.US, "%.5f, %.5f", lat, lon);
  } else {
    File f = download("https://nominatim.openstreetmap.org/search?format=json&limit=1&q=" + URLEncoder.encode(q, "UTF-8"), "geocode:" + q.toLowerCase());
    JSONArray a = loadJSONArray(f.getAbsolutePath());
    if (a == null || a.size() == 0) { f.delete(); throw new Exception("place not found: " + q); }
    JSONObject o = a.getJSONObject(0);
    lat = Double.parseDouble(o.getString("lat")); lon = Double.parseDouble(o.getString("lon"));
    label = o.getString("display_name", q);
  }
  if (Math.abs(lat) > 85 || Math.abs(lon) > 180) throw new Exception("coordinates out of range");
  locLat = lat; locLon = lon; locKey = q; locLabel = label;
  return new double[] { lat, lon };
}

void findLocation() {
  runAsync("Finding location", new Task() {
    public void run() throws Exception {
      double[] ll = resolveLocation();
      statusAsync(String.format(Locale.US, "Location: %.5f, %.5f", ll[0], ll[1]));
    }
  });
}

String locationInfo() {
  if (Double.isNaN(locLat) || !tvLocation.s.trim().equals(locKey)) return "Press Find (or Enter) to look up the place";
  String l = locLabel.length() > 54 ? locLabel.substring(0, 54) + "..." : locLabel;
  return String.format(Locale.US, "%.5f, %.5f\n%s", locLat, locLon, l);
}

// ---------- OpenStreetMap streets (Overpass API) ------------------------------
void fetchStreets() {
  final int type = pStreets.i(), radius = pRadius.i();
  runAsync("Fetching " + STREET_TYPES[type].toLowerCase(), new Task() {
    public void run() throws Exception {
      final double[] ll = resolveLocation();
      String around = "(around:" + radius + "," + String.format(Locale.US, "%.6f,%.6f", ll[0], ll[1]) + ")";
      String body;
      if (type == 1) body = "way[\"highway\"~\"^(motorway|trunk|primary|secondary|tertiary)(_link)?$\"]" + around + ";";
      else if (type == 2) body = "(way[\"natural\"=\"water\"]" + around + ";way[\"waterway\"]" + around + ";relation[\"natural\"=\"water\"]" + around + ";);";
      else if (type == 3) body = "way[\"building\"]" + around + ";";
      else body = "way[\"highway\"]" + around + ";";
      String q = "[out:json][timeout:90];" + body + "out geom;";
      final File f = download("https://overpass-api.de/api/interpreter?data=" + URLEncoder.encode(q, "UTF-8"), q);
      final ArrayList<double[]> lines = parseOverpass(loadJSONObject(f.getAbsolutePath()));
      if (lines.isEmpty()) { f.delete(); throw new Exception("no " + STREET_TYPES[type].toLowerCase() + " found within " + radius + " m"); }
      final String place = shortPlace();
      onMain(new Runnable() { public void run() {
        setGeo(lines, STREET_TYPES[type] + " around " + place, f.getAbsolutePath(), new double[] { ll[0], ll[1], radius });
        pickMode(30);
        setStatus("Streets: " + lines.size() + " lines");
      } });
    }
  });
}

String shortPlace() {
  String p = locLabel.contains(",") && !locLabel.matches("^-?[0-9.]+, -?[0-9.]+$") ? locLabel.substring(0, locLabel.indexOf(',')) : locLabel;
  return p.isEmpty() ? tvLocation.s.trim() : p;
}

ArrayList<double[]> parseOverpass(JSONObject root) {
  ArrayList<double[]> out = new ArrayList<double[]>();
  if (root == null || !root.hasKey("elements")) return out;
  JSONArray els = root.getJSONArray("elements");
  for (int i = 0; i < els.size(); i++) {
    JSONObject e = els.getJSONObject(i);
    if (e.hasKey("geometry")) overpassGeom(e.getJSONArray("geometry"), out);
    if (e.hasKey("members")) {
      JSONArray ms = e.getJSONArray("members");
      for (int k = 0; k < ms.size(); k++) {
        JSONObject m = ms.getJSONObject(k);
        if (m.hasKey("geometry")) overpassGeom(m.getJSONArray("geometry"), out);
      }
    }
  }
  return out;
}

// A list of {lat, lon}; missing nodes (null) split the line.
void overpassGeom(JSONArray g, ArrayList<double[]> out) {
  DoubleList cur = new DoubleList();
  for (int i = 0; i < g.size(); i++) {
    if (g.isNull(i)) { if (cur.size() >= 4) out.add(cur.array()); cur = new DoubleList(); continue; }
    JSONObject p = g.getJSONObject(i);
    cur.append(p.getDouble("lon")); cur.append(p.getDouble("lat"));
  }
  if (cur.size() >= 4) out.add(cur.array());
}

// ---------- routes: GPX / GeoJSON -------------------------------------------
ArrayList<double[]> geoLines;          // each line: lon0, lat0, lon1, lat1, ...
String geoName = "", geoPath = "";
double[] geoFocus;                     // lat, lon, radius (m) of a location fetch, or null

void setGeo(ArrayList<double[]> lines, String name, String path, double[] focus) {
  geoLines = lines; geoName = name; geoPath = path; geoFocus = focus;
  sourceChanged(30);
}

boolean isGeoJSON(JSONObject o) {
  String t = o.getString("type", "");
  return Arrays.asList("FeatureCollection", "Feature", "LineString", "MultiLineString", "Polygon", "MultiPolygon",
    "GeometryCollection", "Point", "MultiPoint").contains(t);
}

boolean loadGeoFile(File f) {
  ArrayList<double[]> lines = new ArrayList<double[]>();
  String name = f.getName();
  try {
    String ext = extOf(f.getName());
    if (ext.equals("gpx")) {
      XML x = loadXML(f.getAbsolutePath());
      gpxCollect(x, lines);
      String n = gpxName(x);
      if (n != null) name = n;
    } else {
      JSONObject o = loadJSONObject(f.getAbsolutePath());
      if (o.hasKey("elements")) lines = parseOverpass(o);
      else geoJSONCollect(o, lines);
    }
  } catch (Exception e) { println("Route error: " + e); }
  if (lines.isEmpty()) { setStatus("No lines found in " + f.getName()); return false; }
  int pts = 0;
  for (double[] l : lines) pts += l.length / 2;
  // a saved street fetch keeps its focus circle (see sourcesJSON)
  setGeo(lines, name, f.getAbsolutePath(), f.getAbsolutePath().equals(geoPath) ? geoFocus : null);
  setStatus("Route loaded: " + name + " (" + lines.size() + " lines, " + pts + " points)");
  return true;
}

String localName(XML x) { String n = x.getName(); return n == null ? "" : n.substring(n.indexOf(':') + 1); }

String gpxName(XML x) {
  for (XML c : x.getChildren()) {
    String n = localName(c);
    if (n.equals("name") && c.getContent() != null && !c.getContent().trim().isEmpty()) return c.getContent().trim();
    if (n.equals("metadata") || n.equals("trk") || n.equals("rte")) { String r = gpxName(c); if (r != null) return r; }
  }
  return null;
}

// Track segments and routes become lines.
void gpxCollect(XML x, ArrayList<double[]> out) {
  String n = localName(x);
  if (n.equals("trkseg") || n.equals("rte")) {
    DoubleList cur = new DoubleList();
    for (XML c : x.getChildren()) {
      String cn = localName(c);
      if (cn.equals("trkpt") || cn.equals("rtept")) { cur.append(c.getDouble("lon")); cur.append(c.getDouble("lat")); }
    }
    if (cur.size() >= 4) out.add(cur.array());
    return;
  }
  for (XML c : x.getChildren()) gpxCollect(c, out);
}

void geoJSONCollect(JSONObject o, ArrayList<double[]> out) {
  String t = o.getString("type", "");
  if (t.equals("FeatureCollection")) {
    JSONArray fs = o.getJSONArray("features");
    for (int i = 0; i < fs.size(); i++) geoJSONCollect(fs.getJSONObject(i), out);
  } else if (t.equals("Feature")) {
    if (!o.isNull("geometry")) geoJSONCollect(o.getJSONObject("geometry"), out);
  } else if (t.equals("GeometryCollection")) {
    JSONArray gs = o.getJSONArray("geometries");
    for (int i = 0; i < gs.size(); i++) geoJSONCollect(gs.getJSONObject(i), out);
  } else if (t.equals("LineString")) {
    geoLine(o.getJSONArray("coordinates"), out);
  } else if (t.equals("MultiLineString") || t.equals("Polygon")) {
    JSONArray a = o.getJSONArray("coordinates");
    for (int i = 0; i < a.size(); i++) geoLine(a.getJSONArray(i), out);
  } else if (t.equals("MultiPolygon")) {
    JSONArray a = o.getJSONArray("coordinates");
    for (int i = 0; i < a.size(); i++) { JSONArray poly = a.getJSONArray(i); for (int k = 0; k < poly.size(); k++) geoLine(poly.getJSONArray(k), out); }
  }
}

void geoLine(JSONArray coords, ArrayList<double[]> out) {
  DoubleList cur = new DoubleList();
  for (int i = 0; i < coords.size(); i++) {
    JSONArray c = coords.getJSONArray(i);
    cur.append(c.getDouble(0)); cur.append(c.getDouble(1));
  }
  if (cur.size() >= 4) out.add(cur.array());
}

// ---------- data series: CSV / JSON -------------------------------------------
ArrayList<float[]> dataSeries;
String dataName = "", dataPath = "";
int dataRowHint = 0;                   // suggested row length (24 for hourly data)

boolean loadDataFile(File f) {
  ArrayList<float[]> series = new ArrayList<float[]>();
  ArrayList<String> names = new ArrayList<String>();
  int hint = 0;
  try {
    if (extOf(f.getName()).equals("json")) {
      String txt = join(loadStrings(f.getAbsolutePath()), "\n").trim();
      Object root = txt.startsWith("[") ? parseJSONArray(txt) : parseJSONObject(txt);
      jsonSeries(root, "", series, names);
      if (txt.contains("\"hourly\"")) hint = 24;
    } else csvSeries(loadStrings(f.getAbsolutePath()), series, names);
  } catch (Exception e) { println("Data error: " + e); }
  if (series.isEmpty()) { setStatus("No numeric data found in " + f.getName()); return false; }
  dataSeries = series;
  dataName = f.getName() + (names.isEmpty() ? "" : " (" + join(names.toArray(new String[0]), ", ") + ")");
  if (dataName.length() > 120) dataName = dataName.substring(0, 117) + "...";
  dataPath = f.getAbsolutePath();
  dataRowHint = hint;
  sourceChanged(31);
  int n = 0;
  for (float[] s : series) n = max(n, s.length);
  setStatus("Data loaded: " + series.size() + (series.size() == 1 ? " series, " : " series, up to ") + n + " values");
  return true;
}

float parseNum(String s, boolean commaDecimal) {
  s = s.trim().replace("\"", "");
  if (s.isEmpty()) return Float.NaN;
  if (commaDecimal) s = s.replace(".", "").replace(',', '.');
  try { return Float.parseFloat(s); } catch (Exception e) { return Float.NaN; }
}

// Every numeric column becomes a series (constant columns are left out). A
// header row gives the names; rows are put oldest-first when a date column
// runs newest-first (as Microsoft 365 usage reports do).
void csvSeries(String[] lines, ArrayList<float[]> out, ArrayList<String> names) {
  ArrayList<String> rows = new ArrayList<String>();
  for (String l : lines) if (l.trim().length() > 0) rows.add(l.startsWith("﻿") ? l.substring(1) : l);
  if (rows.isEmpty()) return;
  String first = rows.get(0);
  char delim = ',';
  int best = -1;
  for (char c : new char[] { ',', ';', '\t', '|' }) {
    int n = first.split(java.util.regex.Pattern.quote(String.valueOf(c)), -1).length;
    if (n > best) { best = n; delim = c; }
  }
  boolean commaDec = delim != ',';
  ArrayList<String[]> cells = new ArrayList<String[]>();
  for (String r : rows) cells.add(splitCsv(r, delim));
  int cols = 0;
  for (String[] c : cells) cols = max(cols, c.length);
  boolean header = false;
  for (String c : cells.get(0)) if (c.trim().length() > 0 && Float.isNaN(parseNum(c, commaDec))) header = true;
  int r0 = header && cells.size() > 1 ? 1 : 0;
  int dateCol = -1;
  for (int c = 0; c < cols && dateCol < 0; c++) {
    String v = c < cells.get(r0).length ? cells.get(r0)[c].trim().replace("\"", "") : "";
    if (v.matches("\\d{4}-\\d{2}-\\d{2}.*")) dateCol = c;
  }
  boolean reverse = false;
  if (dateCol >= 0) {
    String a = cellAt(cells.get(r0), dateCol), b = cellAt(cells.get(cells.size() - 1), dateCol);
    reverse = a.compareTo(b) > 0;
  }
  for (int c = 0; c < cols; c++) {
    int n = cells.size() - r0, good = 0;
    float[] v = new float[n];
    for (int r = 0; r < n; r++) {
      v[r] = parseNum(cellAt(cells.get(r0 + r), c), commaDec);
      if (!Float.isNaN(v[r])) good++;
    }
    if (n < 2 || good < max(2, 0.8 * n)) continue;
    fillGaps(v);
    if (isConstant(v)) continue;
    if (reverse) v = reverse(v);
    out.add(v);
    names.add(header ? cellAt(cells.get(0), c).replace("\"", "").trim() : "column " + (c + 1));
  }
}

String cellAt(String[] row, int c) { return c < row.length ? row[c] : ""; }

// Splits one CSV line, honouring double quotes.
String[] splitCsv(String line, char delim) {
  ArrayList<String> out = new ArrayList<String>();
  StringBuilder cur = new StringBuilder();
  boolean q = false;
  for (int i = 0; i < line.length(); i++) {
    char ch = line.charAt(i);
    if (ch == '"') q = !q;
    else if (ch == delim && !q) { out.add(cur.toString()); cur.setLength(0); }
    else cur.append(ch);
  }
  out.add(cur.toString());
  return out.toArray(new String[0]);
}

void fillGaps(float[] v) {
  float last = Float.NaN;
  for (int i = 0; i < v.length; i++) { if (Float.isNaN(v[i])) v[i] = last; else last = v[i]; }
  last = Float.NaN;
  for (int i = v.length - 1; i >= 0; i--) { if (Float.isNaN(v[i])) v[i] = last; else last = v[i]; }
  for (int i = 0; i < v.length; i++) if (Float.isNaN(v[i])) v[i] = 0;
}

boolean isConstant(float[] v) {
  for (float x : v) if (x != v[0]) return false;
  return true;
}

// Numeric arrays anywhere in the JSON, and arrays of objects (one series per
// numeric key), e.g. {"hourly": {"temperature_2m": [...]}} or [{"value": 3}, ...].
void jsonSeries(Object node, String path, ArrayList<float[]> out, ArrayList<String> names) {
  if (node instanceof JSONObject) {
    JSONObject o = (JSONObject) node;
    for (Object k : o.keys()) jsonSeries(o.get((String) k), (String) k, out, names);
  } else if (node instanceof JSONArray) {
    JSONArray a = (JSONArray) node;
    int n = a.size(), nums = 0, objs = 0;
    for (int i = 0; i < n; i++) {
      Object v = a.get(i);
      if (v instanceof Number) nums++;
      else if (v instanceof JSONObject) objs++;
    }
    if (n >= 3 && nums >= 0.8 * n) {
      float[] v = new float[n];
      for (int i = 0; i < n; i++) { Object x = a.get(i); v[i] = x instanceof Number ? ((Number) x).floatValue() : Float.NaN; }
      fillGaps(v);
      if (!isConstant(v)) { out.add(v); names.add(path.isEmpty() ? "values" : path); }
    } else if (n >= 3 && objs >= 0.8 * n) {
      LinkedHashSet<String> keys = new LinkedHashSet<String>();
      for (int i = 0; i < n; i++) if (a.get(i) instanceof JSONObject) for (Object k : ((JSONObject) a.get(i)).keys()) keys.add((String) k);
      for (String k : keys) {
        float[] v = new float[n];
        int good = 0;
        for (int i = 0; i < n; i++) {
          Object x = a.get(i) instanceof JSONObject ? ((JSONObject) a.get(i)).get(k) : null;
          v[i] = x instanceof Number ? ((Number) x).floatValue() : (x instanceof String ? parseNum((String) x, false) : Float.NaN);
          if (!Float.isNaN(v[i])) good++;
        }
        if (good < 0.8 * n) continue;
        fillGaps(v);
        if (!isConstant(v)) { out.add(v); names.add(k); }
      }
      if (out.isEmpty()) for (int i = 0; i < n; i++) jsonSeries(a.get(i), path, out, names);
    } else {
      for (int i = 0; i < n; i++) if (!(a.get(i) instanceof Number)) jsonSeries(a.get(i), path, out, names);
    }
  }
}

// ---------- weather (Open-Meteo, no key needed) ------------------------------
void fetchWeather() {
  runAsync("Fetching weather", new Task() {
    public void run() throws Exception {
      double[] ll = resolveLocation();
      String url = String.format(Locale.US, "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&hourly=temperature_2m&past_days=92&forecast_days=1&timezone=auto", ll[0], ll[1]);
      final File f = download(url, url + "#" + year() + "-" + month() + "-" + day());   // refreshed daily
      final String place = shortPlace();
      onMain(new Runnable() { public void run() {
        if (!loadDataFile(f)) return;
        dataName = "Hourly temperature, last 92 days, " + place;
        dataRowHint = 24;
        pickMode(31);
      } });
    }
  });
}

// ---------- field grid: CSV matrix, ESRI ASCII grid, heightmap, terrain ------
float[] gridVals; int gridW, gridH, gridVersion = 0;
String gridName = "", gridPath = "";

// Values are normalised to 0..1 (NaN = lowest).
void setGrid(float[] v, int w, int h, String name, String path) {
  float mn = Float.MAX_VALUE, mx = -Float.MAX_VALUE;
  for (float x : v) if (!Float.isNaN(x)) { mn = min(mn, x); mx = max(mx, x); }
  if (mn > mx) { mn = 0; mx = 1; }
  float r = max(mx - mn, 1e-9);
  for (int i = 0; i < v.length; i++) v[i] = Float.isNaN(v[i]) ? 0 : (v[i] - mn) / r;
  gridVals = v; gridW = w; gridH = h; gridName = name; gridPath = path;
  gridVersion++;
  for (Layer L : layers) if (usesField(L.pMode.i()) && L.pField.i() == 2) L.dirty = true;
}

boolean loadGridFile(File f) {
  String ext = extOf(f.getName());
  try {
    if (Arrays.asList("png", "jpg", "jpeg", "gif", "tga").contains(ext)) {
      PImage img = loadImage(f.getAbsolutePath());
      if (img == null || img.width <= 0) throw new Exception("not an image");
      if (max(img.width, img.height) > 800) { img = img.copy(); if (img.width >= img.height) img.resize(800, 0); else img.resize(0, 800); }
      img.loadPixels();
      float[] v = new float[img.width * img.height];
      for (int i = 0; i < v.length; i++) v[i] = brightness(img.pixels[i]);
      setGrid(v, img.width, img.height, "Heightmap " + f.getName(), f.getAbsolutePath());
    } else {
      String[] ls = loadStrings(f.getAbsolutePath());
      float nodata = Float.NaN;
      ArrayList<float[]> rows = new ArrayList<float[]>();
      for (String l : ls) {
        String t = l.trim();
        if (t.isEmpty()) continue;
        String[] kv = splitTokens(t, " \t");
        if (kv.length == 2 && kv[0].toLowerCase().equals("nodata_value")) { nodata = parseNum(kv[1], false); continue; }
        if (kv.length == 2 && kv[0].matches("(?i)[a-z_]+")) continue;           // other .asc header lines
        String[] cs = splitTokens(t, " \t,;");
        float[] r = new float[cs.length];
        int good = 0;
        for (int i = 0; i < cs.length; i++) { r[i] = parseNum(cs[i], false); if (!Float.isNaN(r[i])) good++; }
        if (good >= max(2, cs.length * 0.8)) rows.add(r);
      }
      if (rows.size() < 2) throw new Exception("needs at least 2 rows of numbers");
      int w = Integer.MAX_VALUE;
      for (float[] r : rows) w = min(w, r.length);
      int h = rows.size();
      float[] v = new float[w * h];
      for (int j = 0; j < h; j++) for (int i = 0; i < w; i++) {
        float x = rows.get(j)[i];
        v[j * w + i] = (!Float.isNaN(nodata) && x == nodata) ? Float.NaN : x;
      }
      setGrid(v, w, h, "Grid " + f.getName() + " (" + w + " x " + h + ")", f.getAbsolutePath());
    }
  } catch (Exception e) {
    setStatus("Could not read grid " + f.getName() + ": " + errText(e));
    return false;
  }
  setStatus("Field grid: " + gridName);
  return true;
}

// Terrarium tiles (Mapzen / AWS open data): elevation = R*256 + G + B/256 - 32768.
// A 3 x 3 block of tiles around the location is stitched, cropped so the
// location is in the middle, and written as an ESRI .asc grid in the cache.
void fetchTerrain() {
  final int z = pZoom.i();
  runAsync("Fetching terrain", new Task() {
    public void run() throws Exception {
      double[] ll = resolveLocation();
      double n = Math.pow(2, z), latR = Math.toRadians(ll[0]);
      double fx = (ll[1] + 180) / 360 * n, fy = (1 - Math.log(Math.tan(latR) + 1 / Math.cos(latR)) / Math.PI) / 2 * n;
      int tx = (int) Math.floor(fx), ty = (int) Math.floor(fy), T = 256, S = 3 * T;
      float[] e = new float[S * S];
      for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        int x = ((tx + i) % (int) n + (int) n) % (int) n, y = constrain(ty + j, 0, (int) n - 1);
        File f = download("https://s3.amazonaws.com/elevation-tiles-prod/terrarium/" + z + "/" + x + "/" + y + ".png");
        PImage img = loadImage(f.getAbsolutePath());
        if (img == null || img.width != T) throw new Exception("bad elevation tile " + z + "/" + x + "/" + y);
        img.loadPixels();
        for (int py = 0; py < T; py++) for (int px = 0; px < T; px++) {
          int c = img.pixels[py * T + px];
          e[((j + 1) * T + py) * S + (i + 1) * T + px] = ((c >> 16) & 255) * 256 + ((c >> 8) & 255) + (c & 255) / 256.0 - 32768;
        }
      }
      int cx = (int) ((fx - tx + 1) * T), cy = (int) ((fy - ty + 1) * T);
      int hx = min(cx, S - cx), hy = min(cy, S - cy);
      int w = 2 * hx, h = 2 * hy;
      String[] lines = new String[6 + h];
      lines[0] = "ncols " + w; lines[1] = "nrows " + h; lines[2] = "xllcorner 0"; lines[3] = "yllcorner 0";
      lines[4] = "cellsize 1"; lines[5] = "NODATA_value -99999";
      for (int y = 0; y < h; y++) {
        StringBuilder sb = new StringBuilder();
        for (int x = 0; x < w; x++) { if (x > 0) sb.append(' '); sb.append(round(e[(cy - hy + y) * S + cx - hx + x])); }
        lines[6 + y] = sb.toString();
      }
      final File out = new File(cacheDir(), "terrain_" + z + "_" + String.format(Locale.US, "%.4f_%.4f", ll[0], ll[1]) + ".asc");
      saveStrings(out.getAbsolutePath(), lines);
      final String name = "Terrain around " + shortPlace() + " (zoom " + z + ")";
      onMain(new Runnable() { public void run() {
        if (!loadGridFile(out)) return;
        gridName = name;
        if (!anyLayer(-1, 2)) { Layer L = layers[curLayer]; L.pMode.set(5); L.pField.set(2); L.pEnabled.set(1); }   // terrain reads best as contours
        setStatus(name);
      } });
    }
  });
}

// ---------- field sampling -------------------------------------------------
int fieldSrc = 0;                      // 0 noise, 1 photo, 2 grid (for the layer being generated)
float[] fBuf; int fBufW, fBufH; String fBufKey = "";

boolean usesField(int mode) { return mode == 0 || mode == 1 || mode == 5 || mode == 7; }

// Builds a small, smooth copy of the photo (darkness) or the grid.
void prepareField(int src) {
  if (src == 2 && gridVals == null) src = 0;      // no grid yet: keep using noise
  fieldSrc = src;
  if (src == 0) return;
  String key = src + "," + photoVersion + "," + gridVersion;
  if (fBuf != null && key.equals(fBufKey)) return;
  fBufKey = key;
  int sw, sh;
  if (src == 1) {
    if (photoLum == null) { sw = 300; sh = 400; } else { sw = photoW; sh = photoH; }
  } else { sw = gridW; sh = gridH; }
  int k = max(1, ceil(max(sw, sh) / 300.0));        // box-average down to about 300 px
  fBufW = max(1, sw / k); fBufH = max(1, sh / k);
  fBuf = new float[fBufW * fBufH];
  for (int j = 0; j < fBufH; j++) for (int i = 0; i < fBufW; i++) {
    float sum = 0;
    for (int b = 0; b < k; b++) for (int a = 0; a < k; a++) {
      int x = min(sw - 1, i * k + a), y = min(sh - 1, j * k + b);
      if (src == 2) sum += gridVals[y * sw + x];
      else if (photoLum == null) sum += demoDark((x + 0.5) / sw, (y + 0.5) / sh, sw / (float) sh);
      else sum += 1 - photoLum[y * sw + x];
    }
    fBuf[j * fBufW + i] = sum / (k * k);
  }
}

// Field value 0..1 at page position x, y (mm); the source covers the drawing area.
float fieldSample(float x, float y) {
  float aw = xmax - xmin, ah = ymax - ymin;
  float sc = max(aw / fBufW, ah / fBufH);
  float u = (x - ((xmin + xmax) / 2 - fBufW * sc / 2)) / sc - 0.5, v = (y - ((ymin + ymax) / 2 - fBufH * sc / 2)) / sc - 0.5;
  u = constrain(u, 0, fBufW - 1); v = constrain(v, 0, fBufH - 1);
  int i0 = min((int) u, fBufW - 1), j0 = min((int) v, fBufH - 1), i1 = min(i0 + 1, fBufW - 1), j1 = min(j0 + 1, fBufH - 1);
  float fu = u - i0, fv = v - j0;
  float a = lerp(fBuf[j0 * fBufW + i0], fBuf[j0 * fBufW + i1], fu);
  float b = lerp(fBuf[j1 * fBufW + i0], fBuf[j1 * fBufW + i1], fu);
  return lerp(a, b, fv);
}

// noise(nx, ny) for the Noise field, otherwise the photo / grid at (x, y).
float fieldNoise(float x, float y, float nx, float ny) {
  return fieldSrc == 0 ? noise(nx, ny) : fieldSample(x, y);
}

// ---------- watch folder -----------------------------------------------------
File watchDir;
HashMap<String, Long> watchSeen = new HashMap<String, Long>();
int watchLastMs = 0;

void watchSelected(File f) {
  if (f == null) return;
  final File d = f;
  onMain(new Runnable() { public void run() { startWatching(d); } });
}

void startWatching(File d) {
  watchDir = d;
  watchSeen.clear();
  File[] fs = d.listFiles();
  if (fs != null) for (File f : fs) watchSeen.put(f.getName(), f.lastModified());   // only new files count
  pWatch.set(1);
  setStatus("Watching " + d.getName() + ": drop images, CSV, GPX, SVG, WAV, TXT or presets into it");
}

void pollWatchFolder() {
  if (watchDir == null || !pWatch.on() || millis() - watchLastMs < 1500) return;
  watchLastMs = millis();
  File[] fs = watchDir.listFiles();
  if (fs == null) return;
  Arrays.sort(fs, new Comparator<File>() { public int compare(File a, File b) { return Long.compare(a.lastModified(), b.lastModified()); } });
  long now = System.currentTimeMillis();
  for (File f : fs) {
    if (!f.isFile() || f.getName().startsWith(".") || !KNOWN_EXT.contains(extOf(f.getName()))) continue;
    Long seen = watchSeen.get(f.getName());
    if (seen != null && seen == f.lastModified()) continue;
    if (now - f.lastModified() < 1000) continue;    // still being written
    watchSeen.put(f.getName(), f.lastModified());
    println("Watch folder: " + f.getName());
    if (loadAny(f, true) && pAutoExport.on()) {
      File dir = new File(sketchPath("exports"));
      dir.mkdirs();
      String base = f.getName().substring(0, f.getName().length() - extOf(f.getName()).length() - 1);
      pendingAutoExport = new File(dir, slug(base) + "_" + timestamp() + "." + ext());
    }
    break;                                           // one file per frame, so each gets its own export
  }
}

// ---------- text -> seed / design ---------------------------------------------
int textHash(String s) {                 // FNV-1a, stable across runs and machines
  int h = 0x811c9dc5;
  for (char c : s.trim().toLowerCase().toCharArray()) { h ^= c; h *= 16777619; }
  return h;
}

void seedFromText(Layer L, String s) {
  if (s.trim().isEmpty()) { setStatus("Type a name or phrase first"); return; }
  if (L.pSeed.locked) { setStatus("Seed is locked (right-click it to unlock)"); return; }
  L.pSeed.set(Math.floorMod(textHash(s), 10000));
  setStatus("Seed from \"" + s.trim() + "\": " + L.pSeed.i());
}

// Same text, same design: the text picks a pattern, the seed and the parameters.
void designFromText(Layer L, String s) {
  if (s.trim().isEmpty()) { setStatus("Type a name or phrase first"); return; }
  Random r = new Random(textHash(s));
  IntList modes = new IntList();
  for (int m = 0; m < 30; m++) if (m != 26) modes.append(m);   // patterns that need no source
  L.pMode.set(modes.get(r.nextInt(modes.size())));
  L.pEnabled.set(1);
  randomizeLayer(L, r);
  setStatus("Design from \"" + s.trim() + "\": " + PATTERN_NAMES[L.pMode.i()] + ", seed " + L.pSeed.i());
}

// ---------- file dialogs (called on the dialog thread) ------------------------
void geoSelected(final File f)   { if (f != null) onMain(new Runnable() { public void run() { if (loadGeoFile(f)) pickMode(30); } }); }
void dataSelected(final File f)  { if (f != null) onMain(new Runnable() { public void run() { if (loadDataFile(f)) pickMode(31); } }); }
void svgSelected(final File f)   { if (f != null) onMain(new Runnable() { public void run() { if (loadSvgFile(f)) pickMode(32); } }); }
void audioSelected(final File f) { if (f != null) onMain(new Runnable() { public void run() { if (loadAudioFile(f)) pickMode(33); } }); }
void gridSelected(final File f)  { if (f != null) onMain(new Runnable() { public void run() { if (loadGridFile(f)) pickGrid(); } }); }

void clearSources() {
  geoLines = null; geoName = ""; geoPath = ""; geoFocus = null; sourceChanged(30);
  dataSeries = null; dataName = ""; dataPath = ""; dataRowHint = 0; sourceChanged(31);
  svgShapes = null; svgName = ""; svgPath = ""; sourceChanged(32);
  audioSamples = null; audioName = ""; audioPath = ""; sourceChanged(33);
  gridVals = null; gridName = ""; gridPath = ""; gridVersion++;
  for (Layer L : layers) if (usesField(L.pMode.i()) && L.pField.i() == 2) L.dirty = true;
  setStatus("Sources cleared: the patterns show their demos again");
}

String sourceInfo(int mode) {
  if (mode == 30) {
    if (geoLines == null) return "No route loaded: showing a demo route";
    return shorten(geoName, 60) + "\n" + geoLines.size() + " lines";
  }
  if (mode == 31) {
    if (dataSeries == null) return "No data loaded: showing demo data";
    int n = 0; for (float[] s : dataSeries) n = max(n, s.length);
    return shorten(dataName, 60) + "\n" + dataSeries.size() + " series, " + n + " values" + (dataRowHint > 0 ? ", rows of " + dataRowHint : "");
  }
  if (mode == 32) return svgShapes == null ? "No SVG loaded: showing a demo shape" : shorten(svgName, 60) + "\n" + svgShapes.size() + " paths";
  if (mode == 33) return audioSamples == null ? "No audio loaded: showing a synthetic demo sound"
    : shorten(audioName, 60) + String.format(Locale.US, "\n%.1f s", audioSamples.length / (float) audioRate);
  return "";
}

String shorten(String s, int n) { return s.length() > n ? s.substring(0, n - 3) + "..." : s; }

// ---------- presets --------------------------------------------------------
JSONObject sourcesJSON() {
  JSONObject o = new JSONObject();
  o.setString("location", tvLocation.s);
  o.setString("route", geoPath);
  o.setString("routeName", geoName);
  if (geoFocus != null) { JSONArray a = new JSONArray(); for (double d : geoFocus) a.append(d); o.setJSONArray("routeFocus", a); }
  o.setString("data", dataPath);
  o.setString("dataName", dataName);
  o.setInt("dataRowHint", dataRowHint);
  o.setString("svg", svgPath);
  o.setString("audio", audioPath);
  o.setString("grid", gridPath);
  o.setString("gridName", gridName);
  o.setString("url", lastUrl);
  return o;
}

void applySourcesJSON(JSONObject o) {
  tvLocation.set(o.getString("location", tvLocation.s));
  String p = o.getString("route", "");
  if (!p.isEmpty() && new File(p).exists()) {
    double[] focus = null;
    if (o.hasKey("routeFocus")) { JSONArray a = o.getJSONArray("routeFocus"); focus = new double[] { a.getDouble(0), a.getDouble(1), a.getDouble(2) }; }
    geoPath = p; geoFocus = focus;                   // loadGeoFile keeps the focus for the same file
    if (loadGeoFile(new File(p))) { geoName = o.getString("routeName", geoName); geoFocus = focus; }
  }
  p = o.getString("data", "");
  if (!p.isEmpty() && new File(p).exists() && loadDataFile(new File(p))) {
    dataName = o.getString("dataName", dataName);
    dataRowHint = o.getInt("dataRowHint", dataRowHint);
  }
  p = o.getString("svg", "");
  if (!p.isEmpty() && !p.equals(svgPath) && new File(p).exists()) loadSvgFile(new File(p));
  p = o.getString("audio", "");
  if (!p.isEmpty() && !p.equals(audioPath) && new File(p).exists()) loadAudioFile(new File(p));
  p = o.getString("grid", "");
  if (!p.isEmpty() && new File(p).exists() && loadGridFile(new File(p))) gridName = o.getString("gridName", gridName);
  lastUrl = o.getString("url", "");
}

// ---------- panel ----------------------------------------------------------
void buildSourcesTab(ArrayList<Widget> top) {
  top.add(new Header("LOCATION  (streets, terrain, weather)"));
  top.add(new TextFieldW("Place or lat, lon  (Enter = find)", tvLocation));
  top.add(new RowW(new Widget[] { new InfoW(locationInfo()), new ButtonRow(new String[] { "Find" }, new int[] { 21 }) }, new float[] { 3, 1 }));
  top.add(row(new SliderW(pRadius), new SliderW(pZoom)));
  top.add(new ChoiceW(pStreets, STREET_TYPES.length, null));
  top.add(new ButtonRow(new String[] { "Fetch streets", "Fetch terrain", "Fetch weather" }, new int[] { 18, 19, 20 }));
  top.add(new InfoW("Map data (c) OpenStreetMap contributors (ODbL).\nTerrain: Terrarium tiles. Weather: Open-Meteo."));

  top.add(new Header("FILES"));
  top.add(new ButtonRow(new String[] { "GPX / GeoJSON...", "CSV / JSON...", "SVG..." }, new int[] { 13, 14, 15 }));
  top.add(new ButtonRow(new String[] { "Audio...", "Grid / DEM...", "Photo..." }, new int[] { 16, 17, 9 }));
  StringBuilder sb = new StringBuilder();
  sb.append("Route:  ").append(geoLines == null ? "-" : shorten(geoName, 44)).append('\n');
  sb.append("Data:   ").append(dataSeries == null ? "-" : shorten(dataName, 44)).append('\n');
  sb.append("SVG:    ").append(svgShapes == null ? "-" : shorten(svgName, 44)).append('\n');
  sb.append("Audio:  ").append(audioSamples == null ? "-" : shorten(audioName, 44)).append('\n');
  sb.append("Grid:   ").append(gridVals == null ? "-" : shorten(gridName, 44)).append('\n');
  sb.append("Photo:  ").append(photo == null ? "-" : shorten(new File(photoPath).getName(), 44));
  top.add(new InfoW(sb.toString()));
  top.add(new ButtonRow(new String[] { "Clear sources" }, new int[] { 27 }));

  top.add(new Header("WEB ADDRESS  (image, CSV, JSON, GPX, SVG, WAV, TXT)"));
  top.add(new TextFieldW("URL  (Ctrl+V pastes, Enter = fetch)", tvUrl));
  top.add(new ButtonRow(new String[] { "Fetch URL" }, new int[] { 22 }));

  top.add(new Header("WATCH FOLDER  (new files are loaded automatically)"));
  top.add(new ButtonRow(new String[] { "Choose folder..." }, new int[] { 23 }));
  top.add(row(new ToggleW(pWatch), new ToggleW(pAutoExport)));
  top.add(new InfoW(watchDir == null ? "No folder chosen" : shorten(watchDir.getAbsolutePath(), 60)));

  top.add(new Header("TEXT -> DESIGN  (same text, same result)"));
  top.add(new TextFieldW("Name or phrase", tvSeedText));
  top.add(new ButtonRow(new String[] { "Seed from text", "Design from text" }, new int[] { 24, 25 }));

  top.add(new Header("AI DESIGN  (Claude, needs ANTHROPIC_API_KEY)"));
  top.add(new TextFieldW("Describe the design", tvPrompt));
  top.add(new ButtonRow(new String[] { "Generate design" }, new int[] { 26 }));
  top.add(new InfoW(aiInfo()));
}
