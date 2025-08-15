import json
import os
import tempfile
import time


def atomic_write_json(
    path: str,
    obj,
    *,
    indent: int = 4,
    ensure_ascii: bool = False,
    retries: int = 5,
    delay: float = 0.2,
) -> None:
    """
    Atomically write a JSON file with fsync + same-directory temp file and retries.

    Why this works:
    - We write to a temporary file in the SAME directory as the target, then os.replace().
      On Windows (10/11) this is atomic at the filesystem level.
    - fsync() ensures data hits disk before replace().
    - Retries handle brief locks from sync clients (e.g., OneDrive) or AV scanners.

    Args:
        path: Destination JSON file path.
        obj:  JSON-serializable object.
        indent: json.dump indent.
        ensure_ascii: json.dump ensure_ascii.
        retries: Number of replace retries on transient errors.
        delay: Seconds to sleep between retries.
    """
    dirpath = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(dirpath, exist_ok=True)

    # Create temp file in same directory to keep replace atomic
    fd, tmp_path = tempfile.mkstemp(
        prefix=os.path.basename(path) + ".",
        suffix=".tmp",
        dir=dirpath
    )

    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp:
            json.dump(obj, tmp, indent=indent, ensure_ascii=ensure_ascii)
            tmp.flush()
            os.fsync(tmp.fileno())

        # Try to replace a few times to tolerate brief locks (e.g., OneDrive)
        for i in range(retries):
            try:
                os.replace(tmp_path, path)
                return
            except (PermissionError, OSError) as e:
                if i < retries - 1:
                    time.sleep(delay)
                else:
                    raise e
    finally:
        # If replace succeeded, tmp_path no longer exists. If it failed, clean up.
        try:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
        except OSError:
            # Best-effort cleanup; don't mask the original, more important error.
            pass
