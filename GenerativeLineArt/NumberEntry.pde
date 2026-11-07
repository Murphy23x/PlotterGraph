// Type an exact slider value: double-click a slider or click its value.
// Enter applies, Esc cancels, Tab applies and moves on to the next slider.
// Accepts a decimal comma, and "*2", "/2", "+10" or "-10" to change the
// current value; out-of-range values are clamped (the status bar says so).

Param numParam = null;
TextVal tvNum = new TextVal("", 24);
float sliderPressVal = 0;                // value before the press (a double-click restores it)
boolean numFresh = false;                // the field still shows the old value: typing replaces it

void startNumEdit(Param p) {
  numParam = p;
  tvNum.s = fmtParam(p);
  numFresh = true;
  focusText = tvNum;
}

void applyNum() {
  Param p = numParam;
  if (p == null) return;
  String s = tvNum.s.trim().replace(',', '.').replace(" ", "");
  if (s.isEmpty()) return;
  try {
    float v;
    char op = s.charAt(0);
    if ((op == '*' || op == 'x' || op == '/') && s.length() > 1) {
      float k = Float.parseFloat(s.substring(1));
      v = op == '/' ? p.val / k : p.val * k;
    } else if ((op == '+' || (op == '-' && s.startsWith("--"))) && s.length() > 1) {
      v = p.val + Float.parseFloat(s.substring(op == '+' ? 1 : 2)) * (op == '+' ? 1 : -1);
    } else v = Float.parseFloat(s);
    if (Float.isNaN(v) || Float.isInfinite(v)) throw new NumberFormatException();
    p.set(v);
    if (v < p.min || v > p.max) setStatus(p.label + ": " + fmtNum(v) + " is outside " + fmtNum(p.min) + " .. " + fmtNum(p.max) + ", set to " + fmtParam(p));
  } catch (NumberFormatException e) {
    setStatus("\"" + tvNum.s + "\" is not a number (also: *2, /2, +10, --10)");
  }
}

// Called by typeText for the number field; returns true when it handled the key.
boolean numKey() {
  if (key == ENTER || key == RETURN) { applyNum(); focusText = null; return true; }
  if (key == TAB) {
    applyNum();
    focusText = null;
    boolean back = keyEvent != null && keyEvent.isShiftDown();
    ArrayList<Param> sl = new ArrayList<Param>();
    for (Widget w : panelFlat) if (w instanceof SliderW) sl.add(w.p);
    int i = sl.indexOf(numParam);
    if (i >= 0 && sl.size() > 1) startNumEdit(sl.get((i + (back ? sl.size() - 1 : 1)) % sl.size()));
    return true;
  }
  if (key == CODED && (keyCode == UP || keyCode == DOWN)) {        // nudge while typing
    applyNum();
    Param p = numParam;
    float step = p.isInt ? 1 : (p.max - p.min) / 100.0;
    if (keyEvent != null && keyEvent.isShiftDown()) step *= 10;
    p.set(p.val + (keyCode == UP ? step : -step));
    tvNum.s = fmtParam(p);
    numFresh = true;
    return true;
  }
  if (key >= 32 && key != DELETE && "0123456789.,-+*/x eE".indexOf(key) < 0) return true;   // ignore letters
  // the first key replaces the old value (so "1500", "*2" or "+10" work as typed)
  boolean paste = keyEvent != null && (keyEvent.isControlDown() || keyEvent.isMetaDown()) && keyCode == 'V';
  if (numFresh && (paste || key == BACKSPACE || (key >= 32 && key != DELETE && key != CODED))) {
    tvNum.s = "";
    numFresh = false;
    return key == BACKSPACE;
  }
  return false;
}

// Mouse press on a slider: true when it opened the number field.
boolean sliderPress(SliderW w) {
  boolean onValue = mouseY < w.y + 17 && mouseX > w.x + w.w - 60;
  boolean dbl = mouseEvent != null && mouseEvent.getCount() == 2;
  if (!onValue && !dbl) { sliderPressVal = w.p.val; return false; }
  if (dbl) w.p.set(sliderPressVal);         // the first click of the double-click moved the knob
  startNumEdit(w.p);
  return true;
}

// The value spot of a slider while it is being typed in.
void drawNumField(SliderW w) {
  textSize(12);
  String t = tvNum.s;
  float fw = max(56, textWidth(t) + 16);
  stroke(C_ACCENT); strokeWeight(1); fill(C_FIELD);
  rect(w.x + w.w - fw, w.y - 3, fw, 19, 3);
  if (numFresh) { noStroke(); fill(C_ACCENT, 90); rect(w.x + w.w - 7 - textWidth(t) - 2, w.y - 1, textWidth(t) + 4, 15, 2); }   // selected
  noStroke(); fill(C_TEXT); textAlign(RIGHT, TOP);
  text(t, w.x + w.w - 7, w.y);
  if ((millis() / 500) % 2 == 0) { stroke(C_ACCENT); line(w.x + w.w - 5, w.y - 1, w.x + w.w - 5, w.y + 14); }
}
