"""Keeps each user's Moodle session separate.

When someone signs in, the backend stores their Moodle session cookie under a
new random ID and gives that ID to their app. The app sends it back as
`Authorization: Bearer <id>`, so each request only ever sees its own user's
Moodle session. The mapping is saved to a JSON file so people stay signed in
when the backend restarts.
"""

import json
import logging
import os
import secrets
import threading
from pathlib import Path

logger = logging.getLogger(__name__)

# Holds live Moodle session cookies, so it's gitignored. Override with the
# MOODLE_SESSIONS_FILE environment variable.
DEFAULT_PATH = Path(os.environ.get("MOODLE_SESSIONS_FILE", "moodle_sessions.json"))


class SessionStore:
    """Maps app session IDs to Moodle session tokens. Thread-safe."""

    def __init__(self, path: Path | None = DEFAULT_PATH) -> None:
        # path=None keeps sessions in memory only (used by tests).
        self._path = path
        self._lock = threading.Lock()
        self._tokens: dict[str, str] = self._read()

    def create(self, token: str) -> str:
        """Stores a Moodle token and returns the new session ID for it."""
        session_id = secrets.token_urlsafe(32)
        with self._lock:
            self._tokens[session_id] = token
            self._write()
        return session_id

    def token_for(self, session_id: str | None) -> str | None:
        """The Moodle token for a session ID, or None if there isn't one."""
        if not session_id:
            return None
        with self._lock:
            return self._tokens.get(session_id)

    def update(self, session_id: str, token: str) -> None:
        with self._lock:
            self._tokens[session_id] = token
            self._write()

    def delete(self, session_id: str | None) -> None:
        if not session_id:
            return
        with self._lock:
            if self._tokens.pop(session_id, None) is not None:
                self._write()

    def _read(self) -> dict[str, str]:
        if self._path is None:
            return {}
        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}
        except (OSError, ValueError) as error:
            # A damaged file shouldn't stop the backend from starting; people
            # just sign in again.
            logger.warning("Ignoring unreadable %s: %s", self._path, error)
            return {}
        if not isinstance(data, dict):
            return {}
        return {k: v for k, v in data.items() if isinstance(k, str) and isinstance(v, str)}

    def _write(self) -> None:
        """Saves the sessions. The caller must hold the lock."""
        if self._path is None:
            return
        # Write then rename, so a crash mid-write can't leave a half file.
        tmp = self._path.with_name(self._path.name + ".tmp")
        tmp.write_text(json.dumps(self._tokens), encoding="utf-8")
        try:
            os.chmod(tmp, 0o600)  # owner-only; has no effect on Windows
        except OSError:
            pass
        os.replace(tmp, self._path)
