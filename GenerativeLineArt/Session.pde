// Session: the design is saved to session.json a moment after every change
// and restored when the sketch starts, so closing the window (or a crash)
// never loses work. Ctrl+N starts a fresh design (Undo takes that back).
// Not used in command-line mode.

JSONObject defaultDesign;            // the built-in start design
String lastSessionText = "";
int lastSessionCheck = 0;

File sessionFile() { return new File(sketchPath("session.json")); }

void restoreSession() {
  defaultDesign = presetJSON();
  lastSessionText = defaultDesign.format(-1);
  File f = sessionFile();
  if (!f.exists()) return;
  JSONObject o = null;
  try { o = loadJSONObject(f); } catch (Exception e) {}
  if (o == null || !applyPreset(o)) { setStatus("Could not restore the last session; starting fresh"); return; }
  JSONObject ui = o.getJSONObject("ui");
  if (ui != null) {
    panelTab = constrain(ui.getInt("tab", 0), 0, 2);
    curLayer = constrain(ui.getInt("layer", 0), 0, NUM_LAYERS - 1);
  }
  lastSessionText = sessionText();
  setStatus("Your last design is restored (Ctrl+N = start fresh)");
}

String sessionText() {
  JSONObject o = presetJSON();
  return o.format(-1);
}

void autosaveSession() {
  if (cliMode || defaultDesign == null) return;
  if (millis() - lastSessionCheck < 2000 || millis() - lastChangeMs < 1000 || activeW != null) return;
  lastSessionCheck = millis();
  String t = sessionText();
  JSONObject ui = new JSONObject();
  ui.setInt("tab", panelTab);
  ui.setInt("layer", curLayer);
  String key = t + ui.format(-1);
  if (key.equals(lastSessionText)) return;
  JSONObject o = parseJSONObject(t);
  o.setJSONObject("ui", ui);
  if (o.save(sessionFile(), "indent=2")) lastSessionText = key;
}

void startFresh() {
  if (defaultDesign == null) return;
  commitPending();
  applyPreset(defaultDesign);
  resetView();
  setStatus("Fresh start: Ctrl+Z brings your design back");
}
