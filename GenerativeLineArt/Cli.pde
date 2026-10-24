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
  "  --seed <n>               seed of the layer;  --seed-text <s>  seed from text;  --design-text <s>  design from text",
  "  --prompt <description>   AI design (needs ANTHROPIC_API_KEY)",
  "  --paper A5|A4|A3|Square  --landscape  --portrait",
  "  --format svg|gcode|hpgl  --out <file>  (default exports/lineart_<time>.<ext>)",
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
    if (next != null && !a.equals("--landscape") && !a.equals("--portrait") && !a.equals("--weather") && !a.equals("--help")) i++;
    if (a.equals("--help") || a.equals("-h")) { println(CLI_HELP); cliQuit(0); return; }
    else if (a.equals("--preset")) { File f = cliFile(need(a, next)); if (!applyPreset(loadJSONObject(f.getAbsolutePath()))) cliError("bad preset " + f); }
    else if (a.equals("--input")) { File f = cliFetch(need(a, next)); if (!loadAny(f, true)) cliError("could not load " + next + ": " + status); }
    else if (a.equals("--grid")) { File f = cliFetch(need(a, next)); if (!loadGridFile(f)) cliError(status); pickGrid(); }
    else if (a.equals("--layer")) curLayer = constrain(parseInt(need(a, next)) - 1, 0, NUM_LAYERS - 1);
    else if (a.equals("--location")) tvLocation.set(need(a, next));
    else if (a.equals("--radius")) pRadius.set(parseInt(need(a, next)));
    else if (a.equals("--streets")) {
      if (next != null) { int t = indexOf(new String[] { "all", "major", "water", "buildings" }, next.toLowerCase()); if (t < 0) cliError("unknown street type " + next); pStreets.set(t); }
      fetchStreets();
    }
    else if (a.equals("--terrain")) { if (next != null) pZoom.set(parseInt(next)); fetchTerrain(); }
    else if (a.equals("--weather")) fetchWeather();
    else if (a.equals("--text")) {
      Layer L = layers[curLayer];
      if (L.pMode.i() != 34) { L.pMode.set(34); L.pEnabled.set(1); }
      L.text.set(need(a, next));
    }
    else if (a.equals("--seed")) layers[curLayer].pSeed.set(parseInt(need(a, next)));
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
    else if (a.equals("--batch")) cliBatch = max(1, parseInt(need(a, next)));
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
    if (writeExport(out) == 0) { System.err.println("Error: " + status); cliExitCode = 1; exit(); return true; }
  }
  println(status);
  exit();
  return true;
}
