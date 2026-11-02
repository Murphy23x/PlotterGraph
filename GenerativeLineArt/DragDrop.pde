// Drag and drop: drop files, a folder or a web link onto the window.
// Files load like the Sources tab buttons (by type; presets apply, a layer
// switches to the matching pattern), a folder becomes the watch folder and a
// link from a browser is downloaded.

import java.awt.datatransfer.DataFlavor;
import java.awt.dnd.DnDConstants;
import java.awt.dnd.DropTarget;
import java.awt.dnd.DropTargetAdapter;
import java.awt.dnd.DropTargetDragEvent;
import java.awt.dnd.DropTargetDropEvent;
import java.awt.dnd.DropTargetEvent;

volatile boolean dragHover = false;

void setupDragDrop() {
  Object n = surface.getNative();
  if (!(n instanceof java.awt.Component)) return;      // other renderers: no drop support
  new DropTarget((java.awt.Component) n, DnDConstants.ACTION_COPY, new DropTargetAdapter() {
    public void dragEnter(DropTargetDragEvent e) { dragHover = true; }
    public void dragExit(DropTargetEvent e) { dragHover = false; }
    public void drop(DropTargetDropEvent e) {
      dragHover = false;
      try {
        e.acceptDrop(DnDConstants.ACTION_COPY);
        java.awt.datatransfer.Transferable t = e.getTransferable();
        if (t.isDataFlavorSupported(DataFlavor.javaFileListFlavor)) {
          final List<File> files = new ArrayList<File>();
          for (Object o : (List<?>) t.getTransferData(DataFlavor.javaFileListFlavor)) files.add((File) o);
          onMain(new Runnable() { public void run() { dropFiles(files); } });
        } else if (t.isDataFlavorSupported(DataFlavor.stringFlavor)) {
          final String s = ((String) t.getTransferData(DataFlavor.stringFlavor)).trim();
          onMain(new Runnable() { public void run() { dropText(s); } });
        }
        e.dropComplete(true);
      } catch (Exception ex) {
        e.dropComplete(false);
        statusAsync("Could not read the dropped item: " + errText(ex));
      }
    }
  });
}

void dropFiles(List<File> files) {
  int ok = 0;
  String last = "";
  for (File f : files) {
    if (f.isDirectory()) { startWatching(f); return; }
    if (loadAny(f, true)) { ok++; last = f.getName(); }
  }
  if (files.size() > 1) setStatus("Loaded " + ok + " of " + files.size() + " dropped files");
  else if (ok == 0 && !files.isEmpty()) setStatus("Could not load " + files.get(0).getName() + (status.isEmpty() ? "" : ": " + status));
  else if (ok == 1 && !status.contains(last)) setStatus("Loaded " + last);
}

// A link (or a file:// URI list, as some file managers send it) dropped as text.
void dropText(String s) {
  String first = split(s, '\n')[0].trim();
  if (first.matches("(?i)https?://\\S+")) { tvUrl.set(first); fetchUrl(first); return; }
  if (first.startsWith("file:")) {
    List<File> fs = new ArrayList<File>();
    for (String line : split(s, '\n')) {
      line = line.trim();
      if (line.startsWith("file:")) try { fs.add(new File(URI.create(line))); } catch (Exception e) {}
    }
    dropFiles(fs);
    return;
  }
  setStatus("Drop a file, a folder or a web link (http/https)");
}

// Highlight while something is dragged over the window.
void drawDropOverlay() {
  if (!dragHover) return;
  noStroke(); fill(C_PANEL, 210); rect(0, 0, width, height);
  stroke(C_ACCENT); strokeWeight(3); noFill();
  rect(24, 24, width - 48, height - 48, 14);
  noStroke(); fill(C_TEXT); textAlign(CENTER, CENTER);
  textSize(24); text("Drop to load", width / 2, height / 2 - 18);
  fill(C_DIM); textSize(13);
  text("image, CSV / JSON, GPX / GeoJSON, SVG, audio, grid, text or preset\na folder to watch, or a web link", width / 2, height / 2 + 24);
}
