    #!/usr/bin/env bash
    # lint/run-linter-safe.sh
    # Runs the original raku linter and guarantees a JSON output file (lint-result.json).
    set -euo pipefail

    ARGS=("$@")
    WORKDIR="${WORKDIR:-/workspace}"
    cd "$WORKDIR" || true

    OUT_JSON="lint-result.json"
    LOG_FILE="lint-run.log"

    rm -f "$OUT_JSON" "$LOG_FILE"

    if command -v raku >/dev/null 2>&1; then
      raku lint/mtsx-lint.raku "${ARGS[@]}" > "$OUT_JSON" 2> "$LOG_FILE" || true
      RC=$?
    else
      echo "raku: command not found" > "$LOG_FILE"
      RC=127
    fi

    VALID_JSON=1
    if [ -s "$OUT_JSON" ]; then
      if command -v jq >/dev/null 2>&1; then
        if ! jq -e . "$OUT_JSON" >/dev/null 2>&1; then
          VALID_JSON=0
        fi
      else
        head -c 1 "$OUT_JSON" | grep -qE '[\[{]' || VALID_JSON=0 || true
      fi
    else
      VALID_JSON=0
    fi

    if [ "$VALID_JSON" -eq 1 ] && [ -s "$OUT_JSON" ]; then
      echo "Linter produced valid JSON (exit code: $RC)"
      exit $RC
    fi

    LOG_TAIL=$(tail -n 200 "$LOG_FILE" 2>/dev/null || true)
    BAD_HEAD=$(head -n 80 "$OUT_JSON" 2>/dev/null || true)
    if command -v jq >/dev/null 2>&1; then
      jq -n --arg rc "$RC" --arg log "$LOG_TAIL" --arg head "$BAD_HEAD" '{
        ok: false,
        error: "linter failed or produced invalid/empty JSON",
        exit_code: ($rc | tonumber? // 1),
        log_tail: $log,
        json_head: $head
      }' > "$OUT_JSON"
    else
      # fallback using python for JSON escaping
      python3 - <<'PY' > "$OUT_JSON"
import json,sys,os
rc = int(os.environ.get('RC','1'))
log = sys.stdin.read()
print(json.dumps({"ok": False, "error": "linter failed or produced invalid/empty JSON", "exit_code": rc, "log_tail": log, "json_head": ""}))
PY
    fi

    echo "Wrote fallback $OUT_JSON (linter exit code: $RC). Check $LOG_FILE for details."
    exit $RC
