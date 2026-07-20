"""Drum Lab local server — upload, crop, separate, extract, audit in one tab.

Serves tools/av_debug (the lab page) AND gives the browser a way to run the
heavy Python pipeline it cannot run itself:

  GET  /api/ping                     -> {"ok": true}  (lab uses this to show the prep UI)
  POST /api/separate?name=&shifts=   -> body = cropped WAV bytes; returns {"job": id}
  GET  /api/status/<id>              -> {"state", "log", "result": {stemUrl, eventsUrl}}
  GET  /files/<path>                 -> files under scripts/drums (stems, event JSONs)
  GET  /<anything else>              -> static lab pages from tools/av_debug

The separate+extract work runs in a background thread per job, shelling out to
separate.py / extract.py with the SAME interpreter (sys.executable), so run
this server from the pipeline env:

  conda run -n xene-drums python drum_lab_server.py
  -> open http://127.0.0.1:8123/drum-lab.html

Local tool: binds 127.0.0.1 only; filenames are sanitized; /files/ refuses to
escape the pipeline directory.
"""

from __future__ import annotations

import json
import logging
import re
import subprocess
import sys
import threading
import time
import uuid
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("drum_lab_server")

PIPE_DIR = Path(__file__).resolve().parent
LAB_DIR = (PIPE_DIR / ".." / ".." / "tools" / "av_debug").resolve()
# Lab pages reference shared visualizer JS via ../../web/dancing_points/...
# which the browser normalizes to /web/... — serve that tree read-only too.
WEB_DIR = (PIPE_DIR / ".." / ".." / "web").resolve()
UPLOAD_DIR = PIPE_DIR / "uploads"
PORT = 8123
MAX_UPLOAD_BYTES = 200 * 1024 * 1024

JOBS: dict[str, dict] = {}
JOBS_LOCK = threading.Lock()


def _job_log(job_id, line):
    line = line.rstrip()
    if not line:
        return
    with JOBS_LOCK:
        JOBS[job_id]["log"].append(line)
    logger.info("[job %s] %s", job_id[:8], line)


def _run_step(job_id, cmd):
    """Run one pipeline step, streaming its output into the job log."""
    _job_log(job_id, "$ " + " ".join(str(c) for c in cmd))
    proc = subprocess.Popen(
        [str(c) for c in cmd], cwd=PIPE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        encoding="utf-8", errors="replace",
    )
    for line in proc.stdout:
        # demucs progress bars repaint with \r — keep only the final state per chunk
        _job_log(job_id, line.split("\r")[-1])
    proc.wait()
    if proc.returncode != 0:
        raise RuntimeError(f"step exited {proc.returncode}")


def _process_job(job_id, wav_path, shifts):
    try:
        with JOBS_LOCK:
            JOBS[job_id]["state"] = "separating"
        _run_step(job_id, [sys.executable, PIPE_DIR / "separate.py", wav_path,
                           "--shifts", shifts, "-o", PIPE_DIR / "separated"])

        stem = PIPE_DIR / "separated" / "htdemucs_ft" / wav_path.stem / "drums.wav"
        if not stem.exists():
            raise RuntimeError(f"expected drums stem missing: {stem}")

        with JOBS_LOCK:
            JOBS[job_id]["state"] = "extracting"
        events_out = UPLOAD_DIR / f"{wav_path.stem}.drum-events.json"
        _run_step(job_id, [sys.executable, PIPE_DIR / "extract.py", stem, "-o", events_out])

        # lint gate, in report mode: a FAIL is surfaced to the lab, not fatal
        # to the job (the human decides what to do with a failing chart).
        with JOBS_LOCK:
            JOBS[job_id]["state"] = "linting"
        lint_out = UPLOAD_DIR / f"{wav_path.stem}.lint.json"
        _run_step(job_id, [sys.executable, PIPE_DIR / "lint_events.py", events_out,
                           "--report", lint_out, "--warn-only"])
        lint_summary = None
        try:
            lint = json.loads(lint_out.read_text(encoding="utf-8"))
            lint_summary = {"status": lint["status"], "fails": lint["fails"], "warns": lint["warns"]}
        except Exception as e:
            logger.warning("[job %s] could not parse lint report: %s", job_id[:8], e)

        # per-voice band renders (kick/snare/hat WAVs) — the lab's Voices slots
        with JOBS_LOCK:
            JOBS[job_id]["state"] = "rendering bands"
        _run_step(job_id, [sys.executable, PIPE_DIR / "render_bands.py", stem])

        rel = lambda p: "/files/" + p.relative_to(PIPE_DIR).as_posix()
        with JOBS_LOCK:
            JOBS[job_id]["state"] = "done"
            JOBS[job_id]["finished"] = time.time()
            JOBS[job_id]["result"] = {
                "stemUrl": rel(stem),
                "eventsUrl": rel(events_out),
                "lintUrl": rel(lint_out) if lint_out.exists() else None,
                "lint": lint_summary,
                "bandUrls": _band_urls(stem),
            }
        _job_log(job_id, "job complete (lint: %s)" % (lint_summary["status"] if lint_summary else "?"))
    except Exception as e:  # surface every failure to the browser, never swallow
        logger.exception("[job %s] FAILED", job_id[:8])
        with JOBS_LOCK:
            JOBS[job_id]["state"] = "error"
            JOBS[job_id]["log"].append(f"ERROR: {e}")


def _band_urls(stem):
    """URLs for the per-voice band renders next to a drums stem, if present."""
    bands_dir = stem.parent / f"{stem.stem}_bands"
    urls = {}
    for kind in ("kick", "snare", "hat"):
        p = bands_dir / f"{kind}.wav"
        if p.exists():
            urls[kind] = "/files/" + p.relative_to(PIPE_DIR).as_posix()
    return urls or None


def _latest_from_disk():
    """Newest uploads/<name>.drum-events.json whose separated drums stem exists.

    Keeps 'Load latest' working across server restarts — results live on disk,
    not just in this process's memory.
    """
    candidates = sorted(UPLOAD_DIR.glob("*.drum-events.json"),
                        key=lambda p: p.stat().st_mtime, reverse=True) if UPLOAD_DIR.exists() else []
    for events in candidates:
        stem = PIPE_DIR / "separated" / "htdemucs_ft" / events.name[: -len(".drum-events.json")] / "drums.wav"
        if not stem.exists():
            continue
        lint_path = events.with_name(events.name.replace(".drum-events.json", ".lint.json"))
        lint_summary = None
        if lint_path.exists():
            try:
                lint = json.loads(lint_path.read_text(encoding="utf-8"))
                lint_summary = {"status": lint["status"], "fails": lint["fails"], "warns": lint["warns"]}
            except Exception:
                pass
        rel = lambda p: "/files/" + p.relative_to(PIPE_DIR).as_posix()
        logger.info("[latest] serving from disk: %s", events.name)
        return {"job": "disk", "finishedAt": events.stat().st_mtime,
                "stemUrl": rel(stem), "eventsUrl": rel(events),
                "lintUrl": rel(lint_path) if lint_path.exists() else None,
                "lint": lint_summary, "bandUrls": _band_urls(stem)}
    return None


class LabHandler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):  # route http.server chatter through logging
        logger.debug("[http] " + fmt, *args)

    def _send_json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/api/ping":
            return self._send_json({"ok": True})
        if url.path == "/api/latest":
            # most recently finished job — powers the blob lab's one-click load
            with JOBS_LOCK:
                done = [(jid, j) for jid, j in JOBS.items() if j.get("state") == "done"]
            if done:
                jid, job = max(done, key=lambda kv: kv[1].get("finished", 0))
                return self._send_json({"job": jid, "finishedAt": job.get("finished"),
                                        **job["result"]})
            # no in-memory jobs (server restarted): scan disk for the newest
            # stem+events pair so earlier sessions' results stay one click away
            latest = _latest_from_disk()
            if latest is None:
                return self._send_json({"error": "no completed jobs yet"}, 404)
            return self._send_json(latest)
        if url.path.startswith("/api/status/"):
            job_id = url.path.rsplit("/", 1)[-1]
            with JOBS_LOCK:
                job = JOBS.get(job_id)
                if not job:
                    return self._send_json({"error": "unknown job"}, 404)
                return self._send_json({
                    "state": job["state"],
                    "log": job["log"][-6:],
                    "result": job.get("result"),
                })
        if url.path.startswith("/files/"):
            return self._send_file(PIPE_DIR, url.path[len("/files/"):])
        if url.path.startswith("/web/"):
            return self._send_file(WEB_DIR, url.path[len("/web/"):])
        return super().do_GET()

    def _send_file(self, root, rel):
        import mimetypes

        target = (root / rel).resolve()
        if not str(target).startswith(str(root)) or not target.is_file():
            return self._send_json({"error": "not found"}, 404)
        body = target.read_bytes()
        self.send_response(200)
        ctype = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        url = urlparse(self.path)
        if url.path != "/api/separate":
            return self._send_json({"error": "unknown endpoint"}, 404)

        q = parse_qs(url.query)
        raw_name = (q.get("name") or ["track"])[0]
        shifts = (q.get("shifts") or ["1"])[0]
        if not re.fullmatch(r"[1-9]", shifts):
            return self._send_json({"error": "shifts must be 1-9"}, 400)
        safe = re.sub(r"[^A-Za-z0-9_-]+", "_", Path(raw_name).stem)[:60] or "track"

        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_UPLOAD_BYTES:
            return self._send_json({"error": f"bad upload size {length}"}, 400)
        data = self.rfile.read(length)

        job_id = uuid.uuid4().hex[:12]
        UPLOAD_DIR.mkdir(exist_ok=True)
        wav_path = UPLOAD_DIR / f"{safe}_{job_id}.wav"
        wav_path.write_bytes(data)
        logger.info("[upload] %s: %d bytes -> %s (shifts=%s)", raw_name, length, wav_path.name, shifts)

        with JOBS_LOCK:
            JOBS[job_id] = {"state": "queued", "log": [], "created": time.time()}
        threading.Thread(target=_process_job, args=(job_id, wav_path, shifts), daemon=True).start()
        return self._send_json({"job": job_id})


def main():
    if not LAB_DIR.exists():
        logger.error("[serve] lab dir missing: %s", LAB_DIR)
        raise SystemExit(1)
    handler = partial(LabHandler, directory=str(LAB_DIR))
    server = ThreadingHTTPServer(("127.0.0.1", PORT), handler)
    logger.info("[serve] lab:   http://127.0.0.1:%d/drum-lab.html", PORT)
    logger.info("[serve] files: /files/* -> %s", PIPE_DIR)
    logger.info("[serve] Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("[serve] stopped")


if __name__ == "__main__":
    main()
