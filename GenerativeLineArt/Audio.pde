// Audio pattern (33): a WAV / AIFF / AU file drawn as waveform rows, a
// waveform spiral, or a spectrum "ridgeline" (one line per time slice).
// Read with javax.sound, so no extra library is needed.

import javax.sound.sampled.AudioFormat;
import javax.sound.sampled.AudioInputStream;
import javax.sound.sampled.AudioSystem;

float[] audioSamples;                  // mono, -1..1
int audioRate = 22050;
String audioName = "", audioPath = "";

boolean loadAudioFile(File f) {
  try {
    AudioInputStream in = AudioSystem.getAudioInputStream(f);
    AudioFormat src = in.getFormat();
    int ch = max(1, src.getChannels());
    AudioFormat fmt = new AudioFormat(AudioFormat.Encoding.PCM_SIGNED, src.getSampleRate(), 16, ch, ch * 2, src.getSampleRate(), false);
    byte[] b = readAllBytes(AudioSystem.getAudioInputStream(fmt, in));
    int frames = b.length / (2 * ch);
    if (frames < 64) throw new Exception("file is too short");
    // average down to at most ~22 kHz and at most 8 million samples
    int k = max(1, round(src.getSampleRate() / 22050));
    while (frames / k > 8000000) k++;
    int n = frames / k;
    float[] s = new float[n];
    for (int i = 0; i < n; i++) {
      float sum = 0;
      for (int a = 0; a < k; a++) for (int c = 0; c < ch; c++) {
        int o = ((i * k + a) * ch + c) * 2;
        sum += (short) ((b[o] & 255) | (b[o + 1] << 8)) / 32768.0;
      }
      s[i] = sum / (k * ch);
    }
    audioSamples = s;
    audioRate = max(1, round(src.getSampleRate() / k));
    audioName = f.getName(); audioPath = f.getAbsolutePath();
    sourceChanged(33);
    setStatus(String.format(Locale.US, "Audio loaded: %s (%.1f s)", f.getName(), n / (float) audioRate));
    return true;
  } catch (Exception e) {
    setStatus("Could not read audio " + f.getName() + ": " + errText(e) + " (use WAV, AIFF or AU)");
    return false;
  }
}

void genAudio(ArrayList<ArrayList<PVector>> out) {
  int style = (int) pv(0), lines = (int) pv(1), res = (int) pv(3), bands = (int) pv(4);
  float amp = pv(2), gain = pv(5);
  boolean hide = pv(6) > 0.5;
  float[] s = audioSamples != null ? audioSamples : demoAudio();
  int rate = audioSamples != null ? audioRate : 22050;

  if (style == 2) {                                    // spectrum ridgeline
    float[][] v = new float[lines][];
    float mx = 1e-9;
    for (int j = 0; j < lines; j++) {
      float[] b = spectrumBands(s, rate, (int) ((long) s.length * j / lines), (int) ((long) s.length * (j + 1) / lines), bands);
      for (float x : b) mx = max(mx, x);
      v[j] = b;
    }
    for (int j = 0; j < lines; j++) {
      for (int i = 0; i < v[j].length; i++) v[j][i] = min(1, v[j][i] / mx * gain);
      v[j] = resample(v[j], res + 1);
    }
    ridgelines(out, v, amp, hide);
    return;
  }

  // peak envelope in res buckets per row (or per turn)
  float peak = 1e-9;
  for (float x : s) peak = max(peak, abs(x));
  int buckets = lines * res;
  float[] env = new float[buckets];
  for (int i = 0; i < buckets; i++) {
    int a = (int) ((long) s.length * i / buckets), b = max(a + 1, (int) ((long) s.length * (i + 1) / buckets));
    float m = 0;
    for (int k = a; k < min(b, s.length); k++) m = max(m, abs(s[k]));
    env[i] = min(1, m / peak * gain);
  }
  if (style == 0) {                                    // rows of zig-zag waveform
    float w = xmax - xmin, top = ymin + amp, bot = ymax - amp;
    if (top > bot) top = bot = (ymin + ymax) / 2;
    for (int j = 0; j < lines; j++) {
      float base = lines == 1 ? (top + bot) / 2 : lerp(top, bot, j / (float) (lines - 1));
      ArrayList<PVector> pts = new ArrayList<PVector>(res);
      for (int i = 0; i < res; i++) pts.add(new PVector(xmin + w * i / max(1, res - 1), base + ((i & 1) == 0 ? -1 : 1) * env[j * res + i] * amp));
      emit(out, pts);
    }
  } else {                                             // one spiral, the waveform zig-zags across it
    float cx = (xmin + xmax) / 2, cy = (ymin + ymax) / 2, R = min(xmax - xmin, ymax - ymin) / 2 - amp;
    float r0 = R * 0.08, step = (R - r0) / lines;
    ArrayList<PVector> pts = new ArrayList<PVector>(buckets);
    for (int i = 0; i < buckets; i++) {
      float t = i / (float) res, a = -HALF_PI + TWO_PI * t, r = r0 + step * t + ((i & 1) == 0 ? -1 : 1) * env[i] * min(amp, step * 0.48);
      pts.add(new PVector(cx + cos(a) * r, cy + sin(a) * r));
    }
    emit(out, pts);
  }
}

// Mean log-magnitude in 'bands' log-spaced bands (40 Hz .. 16 kHz) over the
// samples a..b, from up to four Hann-windowed 2048-point FFTs.
float[] spectrumBands(float[] s, int rate, int a, int b, int bands) {
  int N = 2048;
  float[] mag = new float[N / 2];
  int frames = 0;
  for (int f = 0; f < 4; f++) {
    int start = a + (int) ((b - a - N) * (f + 0.5) / 4.0);
    if (b - a < N) start = (a + b) / 2 - N / 2;
    double[] re = new double[N], im = new double[N];
    for (int i = 0; i < N; i++) {
      int k = start + i;
      double w = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (N - 1));
      re[i] = k >= 0 && k < s.length ? s[k] * w : 0;
    }
    fft(re, im);
    for (int i = 0; i < N / 2; i++) mag[i] += (float) Math.sqrt(re[i] * re[i] + im[i] * im[i]);
    frames++;
    if (b - a < N) break;
  }
  float lo = 40, hi = min(16000, rate / 2.0);
  float[] out = new float[bands];
  for (int k = 0; k < bands; k++) {
    float f0 = lo * pow(hi / lo, k / (float) bands), f1 = lo * pow(hi / lo, (k + 1) / (float) bands);
    int i0 = constrain(floor(f0 * N / rate), 1, N / 2 - 1), i1 = constrain(ceil(f1 * N / rate), i0 + 1, N / 2);
    float sum = 0;
    for (int i = i0; i < i1; i++) sum += mag[i];
    out[k] = log(1 + sum / (i1 - i0) / frames);
  }
  return out;
}

// In-place iterative radix-2 FFT (length must be a power of two).
void fft(double[] re, double[] im) {
  int n = re.length;
  for (int i = 1, j = 0; i < n; i++) {
    int bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { double t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
  }
  for (int len = 2; len <= n; len <<= 1) {
    double ang = -2 * Math.PI / len, wr = Math.cos(ang), wi = Math.sin(ang);
    for (int i = 0; i < n; i += len) {
      double cr = 1, ci = 0;
      for (int k = 0; k < len / 2; k++) {
        int p = i + k, q = p + len / 2;
        double xr = re[q] * cr - im[q] * ci, xi = re[q] * ci + im[q] * cr;
        re[q] = re[p] - xr; im[q] = im[p] - xi;
        re[p] += xr; im[p] += xi;
        double t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
      }
    }
  }
}

float[] demoSound;

// Six seconds of synthetic music: a rising chirp, kick drums and a chord.
float[] demoAudio() {
  if (demoSound != null) return demoSound;
  int rate = 22050, n = rate * 6;
  float[] s = new float[n];
  for (int i = 0; i < n; i++) {
    double t = i / (double) rate;
    double chirp = 0.3 * Math.sin(2 * Math.PI * (200 * t + 150 * t * t)) * (0.5 + 0.5 * Math.sin(t * 1.3));
    double bt = t % 0.5, kick = 0.8 * Math.exp(-bt * 18) * Math.sin(2 * Math.PI * 60 * bt * (1 + 2 * Math.exp(-bt * 30)));
    double chord = 0.12 * (Math.sin(2 * Math.PI * 440 * t) + Math.sin(2 * Math.PI * 554.4 * t) + Math.sin(2 * Math.PI * 659.3 * t)) * Math.max(0, Math.sin(Math.PI * t / 3));
    s[i] = (float) Math.max(-1, Math.min(1, chirp + kick + chord));
  }
  demoSound = s;
  return s;
}
