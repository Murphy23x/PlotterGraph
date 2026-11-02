// Command-line mode: build a design from presets and sources without the GUI
// and write the export, e.g. from a script, a scheduled task or a flow.
//
//   Processing cli --sketch=GenerativeLineArt --run --preset presets/x.json \
//     --input data.csv --out exports/x.svg
//
// (An exported application takes the same arguments.) Without --watch the
// window stays hidden and the sketch quits after exporting; the exit code
// is 1 when something failed. Run with --help for every option.

boolean cliMode = false, cliOneShot = false;
String cliOut = null;
int cliBatch = 0, cliExitCode = 0;

class CliAbort extends RuntimeException { CliAbort(String m) { super(m); } }

final String CLI_HELP = String.join("\n",
  "PlotterGraph command-line options:",
  "  --preset <file>          load a preset (.json)",
  "  --input <file|url>       load a source by its type (image, csv, json, gpx, geojson, svg, wav, txt, asc);",
  "                           may be repeated. A layer switches to the matching pattern if none uses it yet",
  "  --grid <file|url>        load a field grid (csv matrix, .asc, heightmap image)",
  "  --layer <1-4>            the layer that --input, --text and --seed act on (default 1)",
  "  --location <place|lat,lon>   for --streets, --terrain and --weather",
  "  --streets [all|major|water|buildings]   --radius <m>   --terrain [zoom]   --weather",
  "  --text <text>            text for the Text pattern ( | = new line)",
  "  --set \"<name>=<value>\"   any parameter by name: the layer's pattern, layer settings (Pattern, Pen colour,",
  "                           Pen width, Scale, ...) or page settings (Paper colour, Margin (mm), ...)",
  "  --list [json]            list every pattern, parameter and setting with its range, then quit",
  "  --seed <n>               seed of the layer;  --seed-text <s>  seed from text;  --design-text <s>  design from text",
  "  --prompt <description>   AI design (needs ANTHROPIC_API_KEY)",
  "  --paper A5|A4|A3|Square  --landscape  --portrait",
  "  --format svg|gcode|hpgl  --out <file>  (default exports/lineart_<time>.<ext>; a .png file is a picture of the design)",
  "  --batch <n>              export n seed variations into exports/batch_<time>/",
  "  --watch <folder>         keep running: load and export every new file dropped into the folder",
  "  --help");

void cliSetup() {
  if (args == null || args.length == 0) return;
  cliMode = true;
  syncJobs = true;
  try { cliArgs(); }
  catch (CliAbort e) { cliQuit(1); }
}

// Quits from setup(): PApplet exits once setup() returns.
void cliQuit(int code) {
  cliExitCode = code;
  cliOneShot = false;
  surface.setVisible(false);
  exit();
}

public void exitActual() { System.exit(cliExitCode); }

void cliArgs() {
  String watch = null;
  for (int i = 0; i < args.length; i++) {
    String a = args[i];
    String next = i + 1 < args.length && !args[i + 1].startsWith("--") ? args[i + 1] : null;
    // flags take no value; --streets and --terrain take one only when it fits
    boolean flag = a.equals("--landscape") || a.equals("--portrait") || a.equals("--weather") || a.equals("--help") || a.equals("-h");
    if (a.equals("--list") && next != null && !next.equalsIgnoreCase("json")) next = null;
    if (a.equals("--streets") && next != null && indexOf(STREET_OPTS, next.toLowerCase()) < 0) next = null;
    if (a.equals("--terrain") && next != null && !next.matches("\\d+")) next = null;
    if (flag) next = null;
    if (next != null) i++;
    if (a.equals("--help") || a.equals("-h")) { println(CLI_HELP); cliQuit(0); return; }
    else if (a.equals("--preset")) { File f = cliFile(need(a, next)); if (!applyPreset(loadJSONObject(f.getAbsolutePath()))) cliError("bad preset " + f); }
    else if (a.equals("--input")) { File f = cliFetch(need(a, next)); if (!loadAny(f, true)) cliError("could not load " + next + ": " + status); }
    else if (a.equals("--grid")) { File f = cliFetch(need(a, next)); if (!loadGridFile(f)) cliError(status); pickGrid(); }
    else if (a.equals("--layer")) curLayer = needInt(a, next, 1, NUM_LAYERS) - 1;
    else if (a.equals("--location")) tvLocation.set(need(a, next));
    else if (a.equals("--radius")) pRadius.set(needInt(a, next, 200, 5000));
    else if (a.equals("--streets")) {
      if (next != null) pStreets.set(indexOf(STREET_OPTS, next.toLowerCase()));
      fetchStreets();
    }
    else if (a.equals("--terrain")) { if (next != null) pZoom.set(needInt(a, next, 6, 14)); fetchTerrain(); }
    else if (a.equals("--weather")) fetchWeather();
    else if (a.equals("--text")) {
      Layer L = layers[curLayer];
      if (L.pMode.i() != 34) { L.pMode.set(34); L.pEnabled.set(1); }
      L.text.set(need(a, next));
    }
    else if (a.equals("--list")) { cliList(next != null); cliQuit(0); return; }
    else if (a.equals("--set")) cliSet(need(a, next));
    else if (a.equals("--seed")) layers[curLayer].pSeed.set(needInt(a, next, 0, 9999));
    else if (a.equals("--seed-text")) seedFromText(layers[curLayer], need(a, next));
    else if (a.equals("--design-text")) designFromText(layers[curLayer], need(a, next));
    else if (a.equals("--prompt")) aiGenerate(need(a, next));
    else if (a.equals("--paper")) { int p = indexOf(PAPER_NAMES, need(a, next)); if (p < 0) cliError("unknown paper " + next); pPaper.set(p); }
    else if (a.equals("--landscape")) pLandscape.set(1);
    else if (a.equals("--portrait")) pLandscape.set(0);
    else if (a.equals("--format")) { int f = indexOf(FORMAT_EXT, need(a, next).toLowerCase()); if (f < 0) cliError("unknown format " + next); pFormat.set(f); }
    else if (a.equals("--out")) {
      cliOut = need(a, next);
      int f = indexOf(FORMAT_EXT, extOf(cliOut));
      if (f >= 0) pFormat.set(f);
    }
    else if (a.equals("--batch")) cliBatch = needInt(a, next, 1, 10000);
    else if (a.equals("--watch")) watch = need(a, next);
    else cliError("unknown option " + a + " (try --help)");
  }
  if (watch != null) {                                   // stay open and keep exporting
    File d = cliFile(watch);
    if (!d.isDirectory()) cliError("not a folder: " + watch);
    syncJobs = false;
    pAutoExport.set(1);
    startWatching(d);
    println("Watching " + d.getAbsolutePath() + " (close the window to stop)");
  } else {
    cliOneShot = true;
    surface.setVisible(false);
  }
}

final String[] STREET_OPTS = { "all", "major", "water", "buildings" };

// A whole number in [lo, hi]; anything else stops the run instead of quietly becoming 0.
int needInt(String opt, String v, int lo, int hi) {
  need(opt, v);
  long n;
  try { n = Long.parseLong(v.trim()); } catch (NumberFormatException e) { cliError(opt + " needs a whole number, not \"" + v + "\""); return lo; }
  if (n < lo || n > hi) cliError(opt + " must be between " + lo + " and " + hi + " (got " + v + ")");
  return (int) Math.max(lo, Math.min(hi, n));
}

String need(String opt, String v) {
  if (v == null) cliError(opt + " needs a value");
  return v;
}

File cliFile(String p) {
  File f = new File(p);
  if (!f.isAbsolute()) f = new File(System.getProperty("user.dir"), p);
  return f;
}

File cliFetch(String p) {
  if (p.matches("(?i)https?://.+")) {
    try { return download(p); } catch (Exception e) { cliError("download failed: " + errText(e)); }
  }
  File f = cliFile(p);
  if (!f.exists()) cliError("file not found: " + f);
  return f;
}

// In command-line mode an error stops the run (exit code 1).
void cliError(String msg) {
  System.err.println("Error: " + msg);
  if (cliMode && syncJobs) throw new CliAbort(msg);
  setStatus(msg);
}

// Called from draw() after the layers were generated. Returns true when the
// sketch is exiting.
boolean cliStep() {
  if (!cliOneShot) return false;
  cliOneShot = false;
  if (cliBatch > 0) {
    pBatch.set(cliBatch);
    batchExport();
  } else {
    File out = cliOut != null ? cliFile(cliOut) : new File(sketchPath("exports"), "lineart_" + timestamp() + "." + ext());
    if (out.getParentFile() != null) out.getParentFile().mkdirs();
    if (extOf(out.getName()).equals("png")) {                // a picture of the design instead of plot data
      if (!writeShareImage(out)) { System.err.println("Error: " + status); cliExitCode = 1; }
      else println("Saved: " + out.getAbsolutePath());
      exit();
      return true;
    }
    if (writeExport(out) == 0) { System.err.println("Error: " + status); cliExitCode = 1; exit(); return true; }
  }
  println(status);
  exit();
  return true;
}

// --list: every pattern with its parameters, the layer settings and the page
// settings, as text or (--list json) as JSON for scripts.
void cliList(boolean json) {
  if (json) {
    JSONObject root = new JSONObject();
    JSONArray pats = new JSONArray();
    for (int m = 0; m < PATTERN_NAMES.length; m++) {
      JSONObject o = new JSONObject();
      o.setString("name", PATTERN_NAMES[m]);
      o.setJSONArray("params", paramsJSON(makeParams(null, m)));
      pats.append(o);
    }
    root.setJSONArray("patterns", pats);
    Layer L = layers[0];
    root.setJSONArray("layer", paramsJSON(layerParams(L)));
    root.setJSONArray("page", paramsJSON(globals));
    println(root.format(2));
    return;
  }
  StringBuilder sb = new StringBuilder("Patterns and their parameters (name [range] default):\n");
  for (int m = 0; m < PATTERN_NAMES.length; m++) sb.append("  ").append(PATTERN_NAMES[m]).append(": ").append(paramsText(makeParams(null, m))).append('\n');
  sb.append("\nLayer settings: ").append(paramsText(layerParams(layers[0]))).append('\n');
  sb.append("\nPage settings: ").append(paramsText(globals)).append('\n');
  sb.append("\nChange any of them with --set \"<name>=<value>\" (choices by name, e.g. --set \"Paper colour=Black\").");
  println(sb.toString());
}

ArrayList<Param> layerParams(Layer L) {
  ArrayList<Param> a = new ArrayList<Param>();
  Collections.addAll(a, L.pEnabled, L.pMode, L.pColor, L.pPen, L.pSeed, L.pScale, L.pRot, L.pOffX, L.pOffY, L.pMask, L.pField);
  return a;
}

String paramsText(ArrayList<Param> ps) {
  StringBuilder sb = new StringBuilder();
  for (int k = 0; k < ps.size(); k++) {
    Param p = ps.get(k);
    if (k > 0) sb.append("; ");
    sb.append(p.label);
    if (p.type == 1) sb.append(" [on/off] ").append(p.on() ? "on" : "off");
    else if (p.type == 2) sb.append(" [").append(join(p.opts, "|")).append("] ").append(p.opts[p.i()]);
    else sb.append(" [").append(fmtNum(p.min)).append("..").append(fmtNum(p.max)).append("] ").append(fmtNum(p.def));
  }
  return sb.toString();
}

JSONArray paramsJSON(ArrayList<Param> ps) {
  JSONArray a = new JSONArray();
  for (Param p : ps) {
    JSONObject o = new JSONObject();
    o.setString("name", p.label);
    o.setString("type", p.type == 1 ? "toggle" : (p.type == 2 ? "choice" : (p.isInt ? "integer" : "number")));
    if (p.type == 2) { JSONArray opts = new JSONArray(); for (String s : p.opts) opts.append(s); o.setJSONArray("options", opts); o.setString("default", p.opts[(int) p.def]); }
    else if (p.type == 1) o.setBoolean("default", p.def > 0.5);
    else { o.setDouble("min", Double.parseDouble(fmtNum(p.min))); o.setDouble("max", Double.parseDouble(fmtNum(p.max))); o.setDouble("default", Double.parseDouble(fmtNum(p.def))); }
    a.append(o);
  }
  return a;
}

// --set "<name>=<value>": the current layer's pattern parameters first, then
// its layer settings, then the page settings. Choices take the option name
// (or its number), toggles on/off/true/false/1/0.
void cliSet(String spec) {
  int eq = spec.indexOf('=');
  if (eq <= 0) cliError("--set needs <name>=<value>, e.g. --set \"Lines=80\"");
  String name = spec.substring(0, eq).trim(), v = spec.substring(eq + 1).trim();
  Layer L = layers[curLayer];
  Param p = findParam(L.params(), name);
  if (p == null) p = findParam(layerParams(L), name);
  if (p == null && paramKey(name, true).equals("pen")) p = L.pColor;
  if (p == null && paramKey(name, true).equals("pattern")) p = L.pMode;
  if (p == null) p = findParam(globals, name);
  if (p == null) {
    ArrayList<String> near = new ArrayList<String>();
    for (Param q : L.params()) near.add(q.label);
    cliError("no parameter \"" + name + "\" (" + PATTERN_NAMES[L.pMode.i()] + " has: " + join(near.toArray(new String[0]), ", ") + "; --list shows all)");
    return;
  }
  float val;
  if (p.type == 2) {
    int i = -1;
    for (int k = 0; k < p.opts.length; k++) if (paramKey(p.opts[k], false).equals(paramKey(v, false))) i = k;
    if (i < 0 && v.matches("\\d+")) i = Integer.parseInt(v);
    if (i < 0 || i >= p.opts.length) { cliError(p.label + " is one of: " + join(p.opts, ", ")); return; }
    val = i;
  } else if (p.type == 1) {
    String b = v.toLowerCase();
    if (b.matches("on|true|yes|1")) val = 1;
    else if (b.matches("off|false|no|0")) val = 0;
    else { cliError(p.label + " is on or off, not \"" + v + "\""); return; }
  } else {
    try { val = Float.parseFloat(v.replace(',', '.')); }
    catch (NumberFormatException e) { cliError(p.label + " needs a number, not \"" + v + "\""); return; }
    if (val < p.min || val > p.max) cliError(p.label + " must be between " + fmtNum(p.min) + " and " + fmtNum(p.max) + " (got " + v + ")");
  }
  p.set(val);
  if (p == L.pMode) L.pEnabled.set(1);
}
