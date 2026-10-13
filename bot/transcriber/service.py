"""
The transcriber — a local HTTP service in front of faster-whisper.

Why this exists as a service rather than a library call: the bot is Node and
faster-whisper is Python, and a model load costs seconds. Spawning a fresh
process per `/stop` would pay that every single time. This loads the model once
and keeps it warm.

It binds to loopback only and requires a token, because it reads a file path off
the wire and there is no reason for anything else on the machine to be able to
say which file.

    python bot/transcriber/service.py

    GET  /health              -> {"ready": true, "model": "turbo", ...}
    POST /transcribe          -> {"segments": [...], "info": {...}}

Request body:
    {"path": "C:/.../seg-3.wav", "language": "de", "vad": true}

Two things in here are load-bearing and were both found the hard way:

  * Audio is decoded with `wave` + numpy and passed as an ndarray. Passing a
    file PATH makes faster-whisper call its PyAV decoder, which invokes
    av.open(..., metadata_errors=...) — a kwarg PyAV 19 removed, so it raises
    TypeError. There is no compatible PyAV wheel for this interpreter either.
    The bot writes the audio, so the format is known and a general decoder buys
    nothing.
  * `segments` comes back as a generator and transcription only happens when it
    is consumed. Returning it unconsumed reports zero segments for a file that
    was fully transcribed — which looks exactly like "the model heard nothing",
    the one answer that must never be silently wrong.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np
from faster_whisper import WhisperModel

TARGET_RATE = 16000  # what Whisper's feature extractor expects
BYTES_PER_SAMPLE = 2  # 16-bit PCM

# One transcription at a time. CTranslate2 is already multi-threaded internally;
# letting two requests run concurrently would not make either faster and would
# multiply peak memory, which is the constraint that actually matters on CPU.
_transcribe_lock = threading.Lock()

_log = logging.getLogger("transcriber")


def load_16k_mono(path: str | os.PathLike) -> np.ndarray:
    """Decode a 16-bit PCM WAV into float32 mono at 16 kHz.

    Rate conversion is linear interpolation. For 48 kHz -> 16 kHz that is a plain
    3:1 decimation, which aliases slightly above ~8 kHz. That is acceptable here
    because speech energy lives well below it and Whisper's own encoder is far
    more forgiving than a measurement would be. If this ever becomes the reason
    a transcript is disputed, this is the first line to replace.
    """
    with wave.open(str(path), "rb") as w:
        if w.getsampwidth() != BYTES_PER_SAMPLE:
            raise ValueError(f"expected 16-bit PCM, got {w.getsampwidth() * 8}-bit")
        channels = w.getnchannels()
        rate = w.getframerate()
        frames = w.getnframes()
        raw = w.readframes(frames)

    data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0

    if channels > 1:
        # Discord carries one source per stream and duplicates it across both
        # channels, so this is the same value twice, not a mixdown of two people.
        data = data.reshape(-1, channels).mean(axis=1)

    if rate != TARGET_RATE and len(data) > 0:
        out_len = int(round(len(data) * TARGET_RATE / rate))
        if out_len > 1:
            data = np.interp(
                np.linspace(0, len(data) - 1, out_len),
                np.arange(len(data)),
                data,
            ).astype(np.float32)

    return data


class Transcriber:
    """Holds the warm model. Constructing this is the slow part."""

    def __init__(self, model_name: str, compute_type: str) -> None:
        self.model_name = model_name
        started = time.time()
        _log.info("loading model %s (%s)...", model_name, compute_type)
        self.model = WhisperModel(model_name, device="cpu", compute_type=compute_type)
        _log.info("model ready in %.1fs", time.time() - started)

    def transcribe(
        self,
        path: str,
        language: str = "de",
        vad: bool = True,
        beam_size: int = 5,
        min_silence_ms: int = 500,
    ) -> dict:
        audio = load_16k_mono(path)
        duration = len(audio) / TARGET_RATE
        rms = float(np.sqrt(np.mean(np.square(audio)))) if len(audio) else 0.0

        if len(audio) == 0:
            return {
                "segments": [],
                "info": {
                    "duration": 0.0,
                    "duration_after_vad": 0.0,
                    "language": language,
                    "language_probability": 0.0,
                    "rms": 0.0,
                },
                "text": "",
            }

        # RMS is reported for every call so an operator can tell "the model heard
        # nothing" apart from "there was nothing to hear". Those need different
        # responses and look identical in the transcript itself.
        _log.info(
            "transcribing %s: %.1fs audio, rms=%.5f, vad=%s", path, duration, rms, vad
        )

        started = time.time()
        with _transcribe_lock:
            segments, info = self.model.transcribe(
                audio,
                language=language,
                beam_size=beam_size,
                vad_filter=vad,
                vad_parameters=dict(min_silence_duration_ms=min_silence_ms) if vad else None,
                word_timestamps=True,
            )
            # Consume the generator. Without this, transcription never runs and
            # the result is an empty list that looks like silence.
            segments = list(segments)

        elapsed = time.time() - started

        rendered = []
        for segment in segments:
            rendered.append(
                {
                    "start": round(segment.start, 3),
                    "end": round(segment.end, 3),
                    "text": segment.text.strip(),
                    "words": [
                        {
                            "start": round(w.start, 3),
                            "end": round(w.end, 3),
                            "word": w.word,
                            "probability": round(w.probability, 4),
                        }
                        for w in (segment.words or [])
                    ],
                }
            )

        text = " ".join(s["text"] for s in rendered).strip()

        _log.info(
            "done in %.1fs (%.1fx realtime): %d segment(s)",
            elapsed,
            (duration / elapsed) if elapsed > 0 else 0.0,
            len(rendered),
        )

        return {
            "segments": rendered,
            "info": {
                "duration": round(duration, 3),
                "duration_after_vad": round(
                    getattr(info, "duration_after_vad", duration), 3
                ),
                "language": info.language,
                "language_probability": round(info.language_probability, 4),
                "rms": round(rms, 6),
                "elapsed_seconds": round(elapsed, 2),
                "realtime_factor": round(duration / elapsed, 2) if elapsed > 0 else None,
            },
            "text": text,
        }


class Handler(BaseHTTPRequestHandler):
    transcriber: Transcriber
    token: str

    # The default handler logs every request to stderr with the full path, which
    # is a file path off the wire. It is not secret, but it is noise.
    def log_message(self, fmt: str, *args) -> None:  # noqa: A002
        _log.debug("%s - %s", self.address_string(), fmt % args)

    def _reply(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorised(self) -> bool:
        header = self.headers.get("Authorization", "")
        expected = f"Bearer {self.token}"
        # Constant-time-ish: compare_digest on the bytes, not `==` on the header.
        import hmac

        return hmac.compare_digest(header.encode("utf-8"), expected.encode("utf-8"))

    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/health":
            self._reply(404, {"error": "not found"})
            return
        self._reply(
            200,
            {
                "ready": True,
                "model": self.transcriber.model_name,
                "device": "cpu",
                "compute_type": "int8",
            },
        )

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/transcribe":
            self._reply(404, {"error": "not found"})
            return

        if not self._authorised():
            self._reply(401, {"error": "unauthorised"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            request = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError) as error:
            self._reply(400, {"error": f"bad request body: {error}"})
            return

        raw_path = request.get("path")
        if not raw_path:
            self._reply(400, {"error": "path is required"})
            return

        path = Path(raw_path)
        # The bot and this service run as the same user on the same machine, so
        # there is no permission boundary to enforce here. Refusing anything that
        # is not a readable .wav still catches the obvious mistake of handing over
        # a path that does not exist, which otherwise surfaces as a wave error
        # with a message nobody can act on.
        if path.suffix.lower() != ".wav":
            self._reply(400, {"error": f"expected a .wav file, got {path.suffix or 'no extension'}"})
            return
        if not path.is_file():
            self._reply(400, {"error": f"no such file: {path}"})
            return

        try:
            result = self.transcriber.transcribe(
                str(path),
                language=request.get("language", "de"),
                vad=bool(request.get("vad", True)),
                beam_size=int(request.get("beam_size", 5)),
                min_silence_ms=int(request.get("min_silence_ms", 500)),
            )
        except wave.Error as error:
            self._reply(400, {"error": f"not a readable 16-bit PCM wav: {error}"})
            return
        except Exception as error:  # noqa: BLE001 - the bot needs the text, not a class
            _log.exception("transcription failed for %s", path)
            self._reply(500, {"error": str(error)})
            return

        self._reply(200, result)


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("TRANSCRIBER_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    host = os.environ.get("TRANSCRIBER_HOST", "127.0.0.1")
    port = int(os.environ.get("TRANSCRIBER_PORT", "8731"))
    model_name = os.environ.get("TRANSCRIBER_MODEL", "turbo")
    compute_type = os.environ.get("TRANSCRIBER_COMPUTE_TYPE", "int8")
    token = os.environ.get("TRANSCRIBER_TOKEN", "").strip()

    if not token:
        # Refusing to start is the point. A transcription service with no token
        # on loopback is a local process that can ask it to read any wav on the
        # account, and "the port is only localhost" is not an access control.
        _log.error("TRANSCRIBER_TOKEN is empty. Refusing to start.")
        sys.exit(1)

    transcriber = Transcriber(model_name, compute_type)

    Handler.transcriber = transcriber
    Handler.token = token

    server = ThreadingHTTPServer((host, port), Handler)
    _log.info("listening on http://%s:%d (model=%s)", host, port, model_name)
    _log.info("bound to loopback only; the token is required on /transcribe")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        _log.info("shutting down")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()