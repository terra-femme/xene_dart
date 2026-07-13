// @ts-check
// Track export — turns the lab's loaded stems + tuned settings into a portable
// "AV track" bundle: one .zip containing a 30s WAV crop of every loaded slot
// plus track.json (crop window + all reactivity/look settings).
//
// Why WAV: browsers can DECODE mp3/m4a but have no native ENCODER. WAV is a
// trivial container we can write ourselves; the producer pipeline then runs
// ffmpeg once to transcode each WAV → mp3 before upload (see docs). Opus/webm
// via MediaRecorder was rejected: playback inside WKWebView is unverified.
//
// Why a zip: a 5-stem export is 6 files; multiple programmatic downloads get
// blocked by browsers. One zip (STORE method — WAV doesn't deflate usefully)
// needs no library: local headers + central directory + CRC32, ~100 lines.
//
// Contract (consumed by the playlist loader in Phase 3):
//   track.json = {
//     version: 1, title, createdAt,
//     crop: { start, duration },          // seconds, in the ORIGINAL timeline
//     files: { original: 'master.wav', vocals: 'vocals.wav', ... },
//     settings: {
//       engine: { sensitivity, attack, decay, source },
//       look:   { mode, color, warp, density, size, rot },
//     },
//   }
// The uploader rewrites file extensions after transcode (.wav → .mp3); slot
// keys are the stable part of the contract, filenames are not.

(function () {
  'use strict';

  // ---------- CRC32 (poly 0xEDB88320, the zip standard) ----------
  const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();

  /** @param {Uint8Array} bytes */
  function crc32(bytes) {
    let c = 0xffffffff;
    for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  }

  // ---------- WAV (16-bit PCM, interleaved) ----------
  /**
   * @param {Float32Array[]} channels  one Float32Array per channel, equal length
   * @param {number} sampleRate
   * @returns {Uint8Array}
   */
  function encodeWav(channels, sampleRate) {
    const numCh = channels.length;
    const frames = channels[0] ? channels[0].length : 0;
    const dataBytes = frames * numCh * 2;
    const buf = new ArrayBuffer(44 + dataBytes);
    const dv = new DataView(buf);

    /** @param {number} off @param {string} s */
    const str = (off, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(off + i, s.charCodeAt(i)); };
    str(0, 'RIFF'); dv.setUint32(4, 36 + dataBytes, true); str(8, 'WAVE');
    str(12, 'fmt '); dv.setUint32(16, 16, true);
    dv.setUint16(20, 1, true);                      // PCM
    dv.setUint16(22, numCh, true);
    dv.setUint32(24, sampleRate, true);
    dv.setUint32(28, sampleRate * numCh * 2, true); // byte rate
    dv.setUint16(32, numCh * 2, true);              // block align
    dv.setUint16(34, 16, true);                     // bits per sample
    str(36, 'data'); dv.setUint32(40, dataBytes, true);

    let off = 44;
    for (let i = 0; i < frames; i++) {
      for (let ch = 0; ch < numCh; ch++) {
        const v = Math.max(-1, Math.min(1, channels[ch][i]));
        dv.setInt16(off, v < 0 ? v * 0x8000 : v * 0x7fff, true);
        off += 2;
      }
    }
    return new Uint8Array(buf);
  }

  /**
   * Slice [start, start+len) seconds out of an AudioBuffer (max 2 channels —
   * the visualizer only ever analyses mono/stereo material).
   * @param {AudioBuffer} buffer @param {number} start @param {number} len
   * @returns {{channels: Float32Array[], sampleRate: number}}
   */
  function sliceBuffer(buffer, start, len) {
    const sr = buffer.sampleRate;
    const s0 = Math.max(0, Math.floor(start * sr));
    const s1 = Math.min(buffer.length, Math.floor((start + len) * sr));
    const n = Math.max(0, s1 - s0);
    const numCh = Math.min(2, buffer.numberOfChannels);
    const channels = [];
    for (let ch = 0; ch < numCh; ch++) {
      const out = new Float32Array(n);
      // copyFromChannel with an offset avoids materialising the whole channel
      buffer.copyFromChannel(out, ch, s0);
      channels.push(out);
    }
    return { channels, sampleRate: sr };
  }

  // ---------- minimal ZIP writer (method 0 = STORE, no compression) ----------
  /** @param {Date} d */
  function dosDateTime(d) {
    const time = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
    const date = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
    return { time, date };
  }

  /**
   * @param {Array<{name: string, data: Uint8Array}>} entries
   * @returns {Blob}
   */
  function buildZip(entries) {
    const enc = new TextEncoder();
    const now = dosDateTime(new Date());
    /** @type {Uint8Array[]} */ const parts = [];
    /** @type {Array<{name: Uint8Array, crc: number, size: number, offset: number}>} */
    const central = [];
    let offset = 0;

    for (const e of entries) {
      const name = enc.encode(e.name);
      const crc = crc32(e.data);
      const head = new DataView(new ArrayBuffer(30));
      head.setUint32(0, 0x04034b50, true);  // local file header
      head.setUint16(4, 20, true);          // version needed
      head.setUint16(6, 0x0800, true);      // flags: UTF-8 names
      head.setUint16(8, 0, true);           // method: STORE
      head.setUint16(10, now.time, true);
      head.setUint16(12, now.date, true);
      head.setUint32(14, crc, true);
      head.setUint32(18, e.data.length, true);
      head.setUint32(22, e.data.length, true);
      head.setUint16(26, name.length, true);
      head.setUint16(28, 0, true);          // extra len
      central.push({ name, crc, size: e.data.length, offset });
      parts.push(new Uint8Array(head.buffer), name, e.data);
      offset += 30 + name.length + e.data.length;
    }

    const cdStart = offset;
    for (const c of central) {
      const cd = new DataView(new ArrayBuffer(46));
      cd.setUint32(0, 0x02014b50, true);    // central directory header
      cd.setUint16(4, 20, true);            // version made by
      cd.setUint16(6, 20, true);            // version needed
      cd.setUint16(8, 0x0800, true);
      cd.setUint16(10, 0, true);
      cd.setUint16(12, now.time, true);
      cd.setUint16(14, now.date, true);
      cd.setUint32(16, c.crc, true);
      cd.setUint32(20, c.size, true);
      cd.setUint32(24, c.size, true);
      cd.setUint16(28, c.name.length, true);
      // extra/comment/disk/attrs all zero
      cd.setUint32(42, c.offset, true);
      parts.push(new Uint8Array(cd.buffer), c.name);
      offset += 46 + c.name.length;
    }

    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true);     // end of central directory
    end.setUint16(8, central.length, true);
    end.setUint16(10, central.length, true);
    end.setUint32(12, offset - cdStart, true);
    end.setUint32(16, cdStart, true);
    parts.push(new Uint8Array(end.buffer));

    return new Blob(/** @type {BlobPart[]} */ (parts), { type: 'application/zip' });
  }

  // ---------- public API ----------
  /** Slot key → exported filename. `original` is the audible master. */
  const SLOT_FILENAME = {
    original: 'master.wav',
    vocals: 'vocals.wav',
    drums: 'drums.wav',
    bass: 'bass.wav',
    other: 'other.wav',
  };

  /** @param {string} s */
  const slugify = (s) =>
    s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'untitled';

  /**
   * Build and download the track bundle.
   * @param {{
   *   buffers: Partial<Record<string, AudioBuffer>>,
   *   title: string,
   *   crop: { start: number, duration: number },
   *   settings: { engine: object, look: object },
   *   engineParams?: object,
   * }} opts
   * @returns {{ fileCount: number, zipName: string }}
   */
  function exportTrack(opts) {
    const { buffers, title, crop, settings, engineParams } = opts;
    const keys = Object.keys(buffers).filter((k) => buffers[k]);
    if (keys.length === 0) throw new Error('no slots loaded');
    console.log('[track-export] exporting', { title, crop, slots: keys });

    /** @type {Array<{name: string, data: Uint8Array}>} */
    const entries = [];
    /** @type {Record<string, string>} */
    const files = {};

    for (const key of keys) {
      const buffer = /** @type {AudioBuffer} */ (buffers[key]);
      const { channels, sampleRate } = sliceBuffer(buffer, crop.start, crop.duration);
      if (!channels[0] || channels[0].length === 0) {
        // stem shorter than the crop start — skip it, but say so loudly
        console.warn('[track-export] slot empty inside crop window, skipping', key);
        continue;
      }
      const name = SLOT_FILENAME[key] || key + '.wav';
      entries.push({ name, data: encodeWav(channels, sampleRate) });
      files[key] = name;
      console.log('[track-export] sliced', key, channels[0].length, 'frames @', sampleRate);
    }
    if (entries.length === 0) throw new Error('crop window is past the end of every loaded slot');

    // Precomputed reactivity chart (Phase 4): lets playlist playback ship only
    // master + vocals. Failure is non-fatal — playback falls back to live DSP.
    let hasChart = false;
    const CG = /** @type {any} */ (window).ChartGen;
    if (CG && engineParams) {
      try {
        const chart = CG.generateChart({ buffers, crop, engineParams });
        entries.push({ name: 'chart.json', data: new TextEncoder().encode(JSON.stringify(chart)) });
        hasChart = true;
      } catch (err) {
        console.warn('[track-export] chart generation failed — bundle ships without one', err);
      }
    }

    const manifest = {
      version: 1,
      title: title || 'Untitled',
      createdAt: new Date().toISOString(),
      crop: { start: +crop.start.toFixed(3), duration: +crop.duration.toFixed(3) },
      files,
      chart: hasChart ? 'chart.json' : null,
      settings,
    };
    entries.push({ name: 'track.json', data: new TextEncoder().encode(JSON.stringify(manifest, null, 2)) });

    const zipName = slugify(manifest.title) + '.avtrack.zip';
    const blob = buildZip(entries);
    console.log('[track-export] zip built', zipName, (blob.size / 1048576).toFixed(1) + 'MB', entries.length, 'entries');

    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = zipName;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 10000);

    return { fileCount: entries.length, zipName };
  }

  /** @type {any} */ (window).TrackExport = { exportTrack };
})();
