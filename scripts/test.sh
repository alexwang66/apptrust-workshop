#!/usr/bin/env bash
set -euo pipefail
mkdir -p reports
rm -f reports/junit.xml reports/junit.json
node --test --test-reporter=junit test/*.test.js > reports/junit.xml
python3 scripts/junit-evidence.py reports/junit.xml reports/junit.json
