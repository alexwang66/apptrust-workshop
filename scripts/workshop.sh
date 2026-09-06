#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -f .env ]]; then set -a; source .env; set +a; fi
export JFROG_CLI_USER_AGENT=${JFROG_CLI_USER_AGENT:-apptrust-codespaces-workshop/1.0}
export CI=true
export JF_URL=${JF_URL:-${JFROG_URL:-}}
: "${JF_URL:?Set JF_URL or JFROG_URL}" "${JF_PROJECT:?Set JF_PROJECT}" "${APP_KEY:?Set APP_KEY}"
: "${APP_VERSION:?Set a new APP_VERSION}" "${DOCKER_REPO_DEV:?Set DOCKER_REPO_DEV}"
JF_SERVER_ID=${JF_SERVER_ID:-workshop}
BUILD_NAME="$APP_KEY-build"
REGISTRY_HOST=${JF_URL#https://}; REGISTRY_HOST=${REGISTRY_HOST%/}
[[ "$REGISTRY_HOST" != */* && "$JF_URL" == https://* ]] || { echo 'Use an HTTPS platform root URL'; exit 1; }
[[ "$APP_KEY" =~ ^[a-z0-9][a-z0-9-]*$ && "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Use a lowercase app key and numeric x.y.z version'; exit 1; }
IMAGE_REF="$REGISTRY_HOST/$DOCKER_REPO_DEV/$APP_KEY:$APP_VERSION"
mkdir -p reports
case "${1:-}" in
  login)
    : "${JF_ACCESS_TOKEN:?Set JF_ACCESS_TOKEN}"
    jf config add "$JF_SERVER_ID" --url "$JF_URL" --access-token "$JF_ACCESS_TOKEN" --interactive=false
    jf apptrust ping --server-id "$JF_SERVER_ID"
    ;;
  init)
    if ! jf apptrust app-create "$APP_KEY" --application-name "$APP_KEY" --project "$JF_PROJECT" \
      --business-criticality medium --maturity-level production --server-id "$JF_SERVER_ID" > reports/app-create.log 2>&1; then
      if ! grep -qi 'already exists' reports/app-create.log; then
        cat reports/app-create.log; exit 1
      fi
      echo "Application already exists: $APP_KEY"
    else
      cat reports/app-create.log
    fi
    ;;
  keygen)
    : "${EVIDENCE_KEY:?Set EVIDENCE_KEY}" "${EVIDENCE_KEY_ALIAS:?Set EVIDENCE_KEY_ALIAS}"
    [[ ! -e "$EVIDENCE_KEY" ]] || { echo 'Signing key already exists; reuse it or choose a new path.'; exit 1; }
    jf evd generate-key-pair --key-file-path "$(dirname "$EVIDENCE_KEY")" \
      --key-file-name "$(basename "$EVIDENCE_KEY" .key)" --key-alias "$EVIDENCE_KEY_ALIAS" \
      --upload-public-key=true --server-id "$JF_SERVER_ID"
    ;;
  build)
    bash scripts/test.sh
    # Keep one image manifest across classic and containerd-backed Docker engines.
    docker build --provenance=false --sbom=false --build-arg "APP_VERSION=$APP_VERSION" -t "$IMAGE_REF" .
    bash scripts/smoke-image.sh "$IMAGE_REF"
    jf docker push "$IMAGE_REF" --project "$JF_PROJECT" --build-name "$BUILD_NAME" \
      --build-number "$APP_VERSION" --server-id "$JF_SERVER_ID"
    jf rt build-add-git "$BUILD_NAME" "$APP_VERSION" --project "$JF_PROJECT" --server-id "$JF_SERVER_ID"
    jf rt build-publish "$BUILD_NAME" "$APP_VERSION" --project "$JF_PROJECT" --server-id "$JF_SERVER_ID"
    docker inspect --format '{{json .RepoDigests}}' "$IMAGE_REF" > reports/image-digests.json
    ;;
  version)
    jf apptrust version-create "$APP_KEY" "$APP_VERSION" \
      --source-type-artifacts "path=$DOCKER_REPO_DEV/$APP_KEY/$APP_VERSION/manifest.json" \
      --sync --server-id "$JF_SERVER_ID"
    jf apptrust version-promote "$APP_KEY" "$APP_VERSION" "${STAGE_DEV:-DEV}" \
      --promotion-type copy --sync --server-id "$JF_SERVER_ID"
    ;;
  evidence)
    : "${EVIDENCE_KEY:?Set EVIDENCE_KEY}" "${EVIDENCE_KEY_ALIAS:?Set EVIDENCE_KEY_ALIAS}"
    # Re-validate the saved report, rather than trusting an editable PASS summary.
    python3 scripts/junit-evidence.py reports/junit.xml reports/junit.json
    jf evd create --application-key "$APP_KEY" --application-version "$APP_VERSION" \
      --predicate reports/junit.json --predicate-type 'http://junit.org/test-results' --provider-id junit \
      --key "$EVIDENCE_KEY" --key-alias "$EVIDENCE_KEY_ALIAS" --server-id "$JF_SERVER_ID"
    ;;
  scan)
    # A PASS predicate is created only when Xray returns valid JSON and exit status 0.
    rm -f reports/xray.json reports/xray-evidence.json
    if ! jf docker scan "$IMAGE_REF" --project "$JF_PROJECT" --fail=true \
      --format simple-json --server-id "$JF_SERVER_ID" > reports/xray.json; then
      cat reports/xray.json >&2
      exit 1
    fi
    python3 scripts/xray-evidence.py reports/xray.json reports/xray-evidence.json "$IMAGE_REF" "$JF_PROJECT"
    ;;
  xray-evidence)
    : "${EVIDENCE_KEY:?Set EVIDENCE_KEY}" "${EVIDENCE_KEY_ALIAS:?Set EVIDENCE_KEY_ALIAS}"
    [[ -s reports/xray-evidence.json ]] || { echo 'Run the successful scan step first.'; exit 1; }
    jf evd create --application-key "$APP_KEY" --application-version "$APP_VERSION" \
      --predicate reports/xray-evidence.json \
      --predicate-type 'https://jfrog.com/evidence/security-scan/v1' --provider-id jfrog-xray \
      --key "$EVIDENCE_KEY" --key-alias "$EVIDENCE_KEY_ALIAS" --server-id "$JF_SERVER_ID"
    ;;
  sonar-evidence)
    : "${EVIDENCE_KEY:?Set EVIDENCE_KEY}" "${EVIDENCE_KEY_ALIAS:?Set EVIDENCE_KEY_ALIAS}" "${SONAR_TOKEN:?Set SONAR_TOKEN}"
    sonar_host=${SONAR_HOST_URL:-https://sonarcloud.io}
    report_task=.scannerwork/report-task.txt
    [[ -s "$report_task" ]] || { echo 'Run the successful SonarQube scan first.'; exit 1; }
    sonar_project=$(awk -F= '$1 == "projectKey" {print $2}' "$report_task")
    sonar_task=$(awk -F= '$1 == "ceTaskId" {print $2}' "$report_task")
    [[ -n "$sonar_project" ]] || { echo 'SonarQube report-task.txt is missing projectKey.'; exit 1; }
    [[ -n "$sonar_task" ]] || { echo 'SonarQube report-task.txt is missing ceTaskId.'; exit 1; }
    rm -f reports/sonar-ce-task.json reports/sonar-quality-gate.json
    analysis_id=''
    for _ in {1..30}; do
      curl -fsS -u "$SONAR_TOKEN:" \
        "$sonar_host/api/ce/task?id=$sonar_task" \
        -o reports/sonar-ce-task.json
      ce_status=$(jq -r '.task.status // empty' reports/sonar-ce-task.json)
      if [[ "$ce_status" == SUCCESS ]]; then
        analysis_id=$(jq -r '.task.analysisId // empty' reports/sonar-ce-task.json)
        break
      fi
      if [[ "$ce_status" == FAILED || "$ce_status" == CANCELED ]]; then
        cat reports/sonar-ce-task.json >&2
        exit 1
      fi
      sleep 5
    done
    [[ -n "$analysis_id" ]] || { echo 'SonarQube analysis did not complete in time.'; exit 1; }
    cp "$report_task" reports/sonar-report-task.txt
    printf 'analysisId=%s\n' "$analysis_id" >> reports/sonar-report-task.txt
    curl -fsS -u "$SONAR_TOKEN:" \
      "$sonar_host/api/qualitygates/project_status?analysisId=$analysis_id" \
      -o reports/sonar-quality-gate.json
    python3 scripts/sonar-evidence.py reports/sonar-report-task.txt reports/sonar-quality-gate.json reports/sonar-evidence.json
    jf evd create --application-key "$APP_KEY" --application-version "$APP_VERSION" \
      --predicate reports/sonar-evidence.json \
      --predicate-type 'https://sonarsource.com/evidence/quality-gate/v1' --provider-id sonarqube \
      --key "$EVIDENCE_KEY" --key-alias "$EVIDENCE_KEY_ALIAS" --server-id "$JF_SERVER_ID"
    ;;
  qa)
    jf apptrust version-promote "$APP_KEY" "$APP_VERSION" "${STAGE_QA:-QA}" \
      --promotion-type copy --sync --server-id "$JF_SERVER_ID"
    ;;
  release)
    jf apptrust version-release "$APP_KEY" "$APP_VERSION" --sync --server-id "$JF_SERVER_ID"
    ;;
  *) echo 'Usage: bash scripts/workshop.sh {login|init|keygen|build|version|evidence|scan|xray-evidence|sonar-evidence|qa|release}'; exit 2;;
esac
