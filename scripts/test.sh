#!/usr/bin/env bash
set -euo pipefail
mkdir -p reports
rm -f reports/junit.xml reports/junit.json
if ! node --test --test-reporter=junit test/*.test.js > reports/junit.xml; then
  cat reports/junit.xml >&2
  exit 1
fi
python3 scripts/junit-evidence.py reports/junit.xml reports/junit.json
