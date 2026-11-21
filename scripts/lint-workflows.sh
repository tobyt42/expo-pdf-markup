#!/usr/bin/env bash
# Lints every GitHub Actions workflow with actionlint (shellcheck is used for `run:` steps
# when it is installed). CI always has actionlint; locally it is skipped with a warning when
# missing, so `npm run qa:ts` still works without it. Install with `brew install actionlint`.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v actionlint >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then
    echo "actionlint is not installed" >&2
    exit 1
  fi
  echo "warning: actionlint not found, skipping workflow lint (brew install actionlint)" >&2
  exit 0
fi

actionlint "$@"
