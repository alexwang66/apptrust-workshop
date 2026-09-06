#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export JFROG_CLI_USER_AGENT=${JFROG_CLI_USER_AGENT:-apptrust-codespaces-workshop/1.0}
JF_SERVER_ID=${JF_SERVER_ID:-demo}
JF_PROJECT=${JF_PROJECT:-alex}
APP_KEY=${APP_KEY:-alex-apptrust-workshop}
template_name='AppTrust workshop JUnit Xray and Sonar evidence template'
rule_name='AppTrust workshop passing JUnit Xray and Sonar evidence rule'
policy_name='AppTrust workshop QA evidence gate with Sonar'
work_dir=$(mktemp -d /tmp/apptrust-policy.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT

jf api '/unifiedpolicy/api/v1/templates?limit=1000' --server-id "$JF_SERVER_ID" > "$work_dir/templates.json"
template_id=$(jq -r --arg name "$template_name" '.items[] | select(.name == $name) | .id' "$work_dir/templates.json" | head -1)
if [[ -z "$template_id" ]]; then
  jq -n --rawfile rego governance/qa-evidence-gate.rego --arg name "$template_name" '{
    name: $name,
    description: "Require verified passing JUnit results, a verified passing JFrog Xray scan, and a verified passing SonarQube quality gate before QA entry",
    category: "quality",
    parameters: [],
    rego: $rego,
    scanners: [],
    version: "1.0.0",
    data_source_type: "evidence"
  }' > "$work_dir/template-create.json"
  jf api /unifiedpolicy/api/v1/templates -X POST -H 'Content-Type: application/json' \
    --input "$work_dir/template-create.json" --server-id "$JF_SERVER_ID" > "$work_dir/template.json"
  template_id=$(jq -er '.id' "$work_dir/template.json")
fi

jf api '/unifiedpolicy/api/v1/rules?limit=1000' --server-id "$JF_SERVER_ID" > "$work_dir/rules.json"
rule_id=$(jq -r --arg name "$rule_name" '.items[] | select(.name == $name) | .id' "$work_dir/rules.json" | head -1)
if [[ -z "$rule_id" ]]; then
  jq -n --arg name "$rule_name" --arg template "$template_id" '{
    name: $name,
    description: "Validate the contents of signed JUnit, Xray, and SonarQube evidence",
    template_id: $template,
    parameters: []
  }' > "$work_dir/rule-create.json"
  jf api /unifiedpolicy/api/v1/rules -X POST -H 'Content-Type: application/json' \
    --input "$work_dir/rule-create.json" --server-id "$JF_SERVER_ID" > "$work_dir/rule.json"
  rule_id=$(jq -er '.id' "$work_dir/rule.json")
fi

jf api '/unifiedpolicy/api/v1/policies?limit=1000' --server-id "$JF_SERVER_ID" > "$work_dir/policies.json"
policy_id=$(jq -r --arg name "$policy_name" '.items[] | select(.name == $name) | .id' "$work_dir/policies.json" | head -1)
if [[ -z "$policy_id" ]]; then
  jq -n --arg name "$policy_name" --arg rule "$rule_id" --arg app "$APP_KEY" '{
    name: $name,
    description: "Block QA entry unless signed JUnit tests, Xray scan evidence, and SonarQube quality gate evidence all pass",
    enabled: true,
    mode: "block",
    action: {type: "certify_to_gate", stage: {key: "QA", gate: "entry"}},
    scope: {type: "application", application_keys: [$app]},
    rule_ids: [$rule],
    waiver_request_config: "manual"
  }' > "$work_dir/policy-create.json"
  jf api /unifiedpolicy/api/v1/policies -X POST -H 'Content-Type: application/json' \
    --input "$work_dir/policy-create.json" --server-id "$JF_SERVER_ID" > "$work_dir/policy.json"
  policy_id=$(jq -er '.id' "$work_dir/policy.json")
fi

printf 'QA gate ready: policy=%s rule=%s template=%s app=%s project=%s\n' \
  "$policy_id" "$rule_id" "$template_id" "$APP_KEY" "$JF_PROJECT"
