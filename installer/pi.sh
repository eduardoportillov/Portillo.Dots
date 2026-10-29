#!/usr/bin/env bash

configure_pi() {
  local directory="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" result
  result="$(python3 -B "$REPO_DIR/pi/configure.py" "$REPO_DIR/pi/compaction.json" "$directory/settings.json")" \
    || { warn 'Pi settings were not changed; resolve the error and retry'; return 1; }
  record_event "$result" "Pi global compaction settings ($directory/settings.json)"
}
