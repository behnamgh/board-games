#!/usr/bin/env bash
#
# Manually refresh the board game collection from BoardGameGeek and publish it to GitHub.
# Fetches XML from https://boardgamegeek.com/xmlapi2/collection with
# username from config.ini, own=1, and stats=1; parses it into the SQLite database.
# Game details and play history are fetched separately to populate site filters.
# Run this from your own machine whenever you want fresh data:
#
#   ./update.sh                # fetch + build + upload to GitHub
#   ./update.sh --no_upload    # fetch + build locally only, no upload
#   ./update.sh --debug        # verbose output (prints requests/responses)
#
# First run creates an isolated .venv and installs dependencies.
# First upload opens your browser once to authorize GitHub (token cached in ~/.mybgg/token.json).
#
# BGG API authorization: export BGG_API_TOKEN with your registered application's
# token from https://boardgamegeek.com/applications before running this script.
set -euo pipefail

# Validate before installing dependencies or contacting BGG. The token stays in
# the environment and is never written to config.ini or passed on the command line.
if [[ -z "${BGG_API_TOKEN//[[:space:]]/}" ]]; then
  echo "ERROR: set BGG_API_TOKEN to your BGG application token before running update.sh." >&2
  echo "Example: export BGG_API_TOKEN='your-application-token'" >&2
  exit 1
fi
export BGG_API_TOKEN

cd "$(dirname "$0")"

# Pick a Python. Prefer 3.12 because scripts/requirements.txt is pinned for it.
PY=""
for cand in python3.12 python3.13 python3.11 python3; do
  if command -v "$cand" >/dev/null 2>&1; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
  echo "ERROR: no python3 found. Install it with: brew install python@3.12" >&2
  exit 1
fi

# Some Homebrew Python builds link to macOS's older Expat library. Prefer the
# installed Homebrew library if the default XML parser import fails. Keep this
# override scoped to this script and its children.
if ! "$PY" -c "import xml.parsers.expat" >/dev/null 2>&1; then
  if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    EXPAT_PREFIX="$(brew --prefix expat 2>/dev/null || true)"
    if [[ -n "$EXPAT_PREFIX" && -f "$EXPAT_PREFIX/lib/libexpat.1.dylib" ]]; then
      export DYLD_LIBRARY_PATH="$EXPAT_PREFIX/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
    fi
  fi
fi

# Preflight before creating the virtual environment or downloading data.
if ! "$PY" -c "import xml.parsers.expat" >/dev/null 2>&1; then
  echo "ERROR: '$PY' cannot load its XML parser (pyexpat)." >&2
  "$PY" -c "import xml.parsers.expat" >&2
  echo "On Homebrew, try: brew reinstall expat python@3.12" >&2
  exit 1
fi

if [ ! -d .venv ]; then
  echo "First run: creating .venv with $PY and installing dependencies..."
  "$PY" -m venv .venv
  .venv/bin/python -m pip install --quiet --upgrade pip
  .venv/bin/python -m pip install --quiet -r scripts/requirements.txt
fi

exec .venv/bin/python scripts/download_and_index.py "$@"
