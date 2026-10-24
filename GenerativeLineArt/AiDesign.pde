// AI design: describe a design in words, Claude returns a preset.
// ------------------------------------------------------------------
// Needs an Anthropic API key in the ANTHROPIC_API_KEY environment variable
// (set it before starting Processing; ANTHROPIC_BASE_URL optionally points
// at a gateway). The prompt, the list of patterns and
// their parameters, and the names of loaded sources are sent to the
// Anthropic API; the answer is a JSON design (structured output) that is
// applied like a preset, so Undo takes it back.

final String AI_MODEL = "claude-opus-5-5";
String aiUrl() {                       // ANTHROPIC_BASE_URL points at a gateway or proxy, as in the SDKs
  String b = System.getenv("ANTHROPIC_BASE_URL");
  if (b == null || b.trim().isEmpty()) b = "https://api.anthropic.com";
  return b.trim().replaceAll("/+$", "") + "/v1/messages";
}
String aiSummary = "";

String aiKey() {
  String k = System.getenv("ANTHROPIC_API_KEY");
  return k == null || k.trim().isEmpty() ? null : k.trim();
}

String aiInfo() {
  if (aiKey() == null) return "ANTHROPIC_API_KEY is not set: start Processing\nfrom a shell where it is (see README).";
  return aiSummary.isEmpty() ? "Example: \"calm ocean waves in two blues, A3 landscape\"" : shorten(aiSummary, 120);
}

void aiGenerate(String prompt0) {
  final String prompt = prompt0.trim();
  if (prompt.isEmpty()) { setStatus("Describe the design first"); return; }
  final String key = aiKey();
  if (key == null) { setStatus("Set ANTHROPIC_API_KEY to use AI design (see README)"); return; }
  final String body = aiRequest(prompt).format(-1);
  runAsync("Designing with Claude", new Task() {
    public void run() throws Exception {
      byte[] b = httpRequest(aiUrl(), body, new String[] {
        "x-api-key", key, "anthropic-version", "2026-10-21", "content-type", "application/json",
        "anthropic-beta", "server-side-fallback-2026-07-01" });
      JSONObject res = parseJSONObject(new String(b, "UTF-8"));
      String stop = res.getString("stop_reason", "");
      if (stop.equals("refusal")) throw new Exception("the request was declined; try wording it differently");
      if (stop.equals("max_tokens")) throw new Exception("the answer was cut off; try a simpler description");
      String text = "";
      JSONArray content = res.getJSONArray("content");
      for (int i = 0; i < content.size(); i++) {
        JSONObject c = content.getJSONObject(i);
        if (c.getString("type", "").equals("text")) text += c.getString("text", "");
      }
      final JSONObject design = parseJSONObject(text);
      if (design == null) throw new Exception("no design in the answer");
      onMain(new Runnable() { public void run() { applyAiDesign(design); } });
    }
  });
}

JSONObject aiRequest(String prompt) {
  JSONObject req = new JSONObject();
  req.setString("model", AI_MODEL);
  req.setInt("max_tokens", 16000);
  req.setString("fallbacks", "default");
  JSONObject oc = new JSONObject();
  oc.setString("effort", "low");
  JSONObject fmt = new JSONObject();
  fmt.setString("type", "json_schema");
  fmt.setJSONObject("schema", aiSchema());
  oc.setJSONObject("format", fmt);
  req.setJSONObject("output_config", oc);
  req.setString("system", aiSystemPrompt());
  JSONArray msgs = new JSONArray();
  JSONObject m = new JSONObject();
  m.setString("role", "user");
  m.setString("content", prompt);
  msgs.append(m);
  req.setJSONArray("messages", msgs);
  return req;
}

String aiSystemPrompt() {
  StringBuilder sb = new StringBuilder();
  sb.append("You design artwork for PlotterGraph, a generative line-art tool for pen plotters. ")
    .append("A design has 1 to 4 layers; each layer is drawn by one pen, so give layers different pen colours unless the user asks otherwise. ")
    .append("Layers are drawn on top of each other on the same page, so combine patterns that work together. ")
    .append("For each layer pick a pattern, a seed (0-9999), a pen colour, a pen width in mm (0.2-0.8 is typical), a scale (0.1-2, usually 1) and a rotation in degrees. ")
    .append("In 'params' list only the parameters you want to change, by their exact name; the rest keep their defaults. ")
    .append("Choice parameters take the option index (0 = first option); toggles take 0 or 1. Stay inside the given ranges. ")
    .append("Put the words for the Text pattern in 'text' (use | for a new line); leave 'text' empty for other patterns. ")
    .append("Image, Route, Data lines, SVG import and Audio draw a loaded source (or a demo when nothing is loaded): ")
    .append("use them only when the user asks for photos, maps, data, an SVG or sound. ")
    .append("Write 'summary' as one short sentence describing the design, in the user's language.\n\n");
  sb.append("Loaded sources: ").append(loadedSourcesText()).append("\n");
  sb.append("Current paper: ").append(PAPER_NAMES[pPaper.i()]).append(pLandscape.on() ? " landscape" : " portrait").append("\n\n");
  sb.append("Patterns and their parameters (name [min..max] default):\n");
  for (int m = 0; m < PATTERN_NAMES.length; m++) {
    sb.append("- ").append(PATTERN_NAMES[m]).append(": ");
    ArrayList<Param> ps = makeParams(null, m);
    for (int k = 0; k < ps.size(); k++) {
      Param p = ps.get(k);
      if (k > 0) sb.append("; ");
      sb.append(p.label);
      if (p.type == 1) sb.append(" [toggle] ").append(p.i());
      else if (p.type == 2) {
        sb.append(" [");
        for (int o = 0; o < p.opts.length; o++) sb.append(o > 0 ? ", " : "").append(o).append('=').append(p.opts[o]);
        sb.append("] ").append(p.i());
      } else sb.append(" [").append(fmtNum(p.min)).append("..").append(fmtNum(p.max)).append("] ").append(fmtNum(p.def));
    }
    sb.append('\n');
  }
  return sb.toString();
}

String fmtNum(float v) {
  if (v == round(v)) return str(round(v));
  String s = String.format(Locale.US, "%.4g", v);
  return s.contains("e") ? s : s.replaceAll("0+$", "").replaceAll("\\.$", "");
}

String loadedSourcesText() {
  ArrayList<String> s = new ArrayList<String>();
  if (photo != null) s.add("photo " + new File(photoPath).getName());
  if (geoLines != null) s.add("route " + geoName);
  if (dataSeries != null) s.add("data " + dataName);
  if (svgShapes != null) s.add("SVG " + svgName);
  if (audioSamples != null) s.add("audio " + audioName);
  if (gridVals != null) s.add("field grid " + gridName + " (fields: Flow field, Wave lines, Contour map, Hatch shading)");
  return s.isEmpty() ? "none" : join(s.toArray(new String[0]), "; ");
}

JSONObject aiSchema() {
  JSONObject param = obj(new String[] { "name", "value" }, new JSONObject[] { type("string"), type("number") });
  JSONObject layer = obj(
    new String[] { "pattern", "seed", "penColour", "penWidth", "scale", "rotate", "text", "params" },
    new JSONObject[] { enumOf(PATTERN_NAMES), type("integer"), enumOf(PEN_NAMES), type("number"), type("number"),
      type("number"), type("string"), arrayOf(param) });
  return obj(new String[] { "summary", "paper", "landscape", "layers" },
    new JSONObject[] { type("string"), enumOf(PAPER_NAMES), type("boolean"), arrayOf(layer) });
}

JSONObject type(String t) { JSONObject o = new JSONObject(); o.setString("type", t); return o; }

JSONObject enumOf(String[] vals) {
  JSONObject o = type("string");
  JSONArray a = new JSONArray();
  for (String v : vals) a.append(v);
  o.setJSONArray("enum", a);
  return o;
}

JSONObject arrayOf(JSONObject items) { JSONObject o = type("array"); o.setJSONObject("items", items); return o; }

JSONObject obj(String[] keys, JSONObject[] props) {
  JSONObject o = type("object");
  JSONObject p = new JSONObject();
  JSONArray req = new JSONArray();
  for (int i = 0; i < keys.length; i++) { p.setJSONObject(keys[i], props[i]); req.append(keys[i]); }
  o.setJSONObject("properties", p);
  o.setJSONArray("required", req);
  o.setBoolean("additionalProperties", false);
  return o;
}

// Turns the answer into a preset (keeping the page and output settings).
void applyAiDesign(JSONObject d) {
  JSONObject root = new JSONObject();
  root.setString("paper", d.getString("paper", PAPER_NAMES[pPaper.i()]));
  root.setBoolean("landscape", d.getBoolean("landscape", pLandscape.on()));
  root.setFloat("margin", pMargin.val);
  root.setBoolean("optimizeTravel", pOptimize.on());
  root.setBoolean("filePerLayer", pSeparate.on());
  root.setString("maskFont", maskFontName);
  JSONArray in = d.getJSONArray("layers"), outL = new JSONArray();
  for (int i = 0; i < min(NUM_LAYERS, in.size()); i++) {
    JSONObject a = in.getJSONObject(i), o = new JSONObject();
    String pat = a.getString("pattern", PATTERN_NAMES[0]);
    o.setBoolean("enabled", true);
    o.setString("pattern", pat);
    o.setInt("seed", Math.floorMod(a.getInt("seed", 1), 10000));
    o.setString("penColour", a.getString("penColour", PEN_NAMES[i % PEN_NAMES.length]));
    o.setFloat("penWidth", a.getFloat("penWidth", 0.4));
    o.setFloat("scale", a.getFloat("scale", 1));
    o.setFloat("rotate", a.getFloat("rotate", 0));
    o.setString("text", a.getString("text", ""));
    o.setString("field", layers[i].pMode.i() == indexOf(PATTERN_NAMES, pat) ? FIELD_NAMES[layers[i].pField.i()] : "Noise");
    JSONObject named = new JSONObject();
    JSONArray ps = a.getJSONArray("params");
    for (int k = 0; k < ps.size(); k++) named.setFloat(ps.getJSONObject(k).getString("name", ""), ps.getJSONObject(k).getFloat("value", 0));
    JSONObject pp = new JSONObject();
    pp.setJSONObject(pat, named);
    o.setJSONObject("params", pp);
    outL.append(o);
  }
  root.setJSONArray("layers", outL);
  // a pattern's other parameters go back to their defaults, so the design matches the answer
  for (int i = 0; i < min(NUM_LAYERS, in.size()); i++) {
    int m = indexOf(PATTERN_NAMES, in.getJSONObject(i).getString("pattern", ""));
    if (m >= 0) for (Param p : layers[i].modeParams.get(m)) p.set(p.def);
  }
  if (!applyPreset(root)) return;
  aiSummary = d.getString("summary", "");
  setStatus("AI design: " + (aiSummary.isEmpty() ? "applied" : aiSummary));
  if (syncJobs) println("AI design: " + aiSummary);
}
