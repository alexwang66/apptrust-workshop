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
    # Preserve the actual scan response. Never manufacture PASS evidence from text matching.
    jf docker scan "$IMAGE_REF" --project "$JF_PROJECT" --fail=true --server-id "$JF_SERVER_ID" 2>&1 | tee reports/xray.log
    ;;
  qa)
    jf apptrust version-promote "$APP_KEY" "$APP_VERSION" "${STAGE_QA:-QA}" \
      --promotion-type copy --sync --server-id "$JF_SERVER_ID"
    ;;
  release)
    jf apptrust version-release "$APP_KEY" "$APP_VERSION" --sync --server-id "$JF_SERVER_ID"
    ;;
  *) echo 'Usage: bash scripts/workshop.sh {login|init|keygen|build|version|evidence|scan|qa|release}'; exit 2;;
esac
