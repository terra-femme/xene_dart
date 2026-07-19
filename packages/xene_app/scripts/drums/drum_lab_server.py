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

        rel = lambda p: "/files/" + p.relative_to(PIPE_DIR).as_posix()
        with JOBS_LOCK:
            JOBS[job_id]["state"] = "done"
            JOBS[job_id]["result"] = {"stemUrl": rel(stem), "eventsUrl": rel(events_out)}
        _job_log(job_id, "job complete")
    except Exception as e:  # surface every failure to the browser, never swallow
        logger.exception("[job %s] FAILED", job_id[:8])
        with JOBS_LOCK:
            JOBS[job_id]["state"] = "error"
            JOBS[job_id]["log"].append(f"ERROR: {e}")


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
            target = (PIPE_DIR / url.path[len("/files/"):]).resolve()
            if not str(target).startswith(str(PIPE_DIR)) or not target.is_file():
                return self._send_json({"error": "not found"}, 404)
            body = target.read_bytes()
            self.send_response(200)
            ctype = "application/json" if target.suffix == ".json" else "audio/wav"
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        return super().do_GET()

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
