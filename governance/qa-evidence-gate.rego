package curation.policies
import rego.v1

release := input.data

release_evidence := [e | some e in object.get(release, "evidenceConnection", {"edges": []}).edges]

artifact_evidence := [ev |
    some artifact in object.get(release, "artifactsConnection", {"edges": []}).edges
    some ev in object.get(object.get(artifact, "node", {}), "evidenceConnection", {"edges": []}).edges
]

build_evidence := [ev |
    some build in object.get(release, "fromBuilds", [])
    some ev in object.get(build, "evidenceConnection", {"edges": []}).edges
]

all_evidence := array.concat(release_evidence, array.concat(artifact_evidence, build_evidence))

predicate(node) := node.predicate if {
    is_object(node.predicate)
} else := json.unmarshal(node.predicate) if {
    is_string(node.predicate)
}

valid_scan(value) if {
    is_object(value)
} else if {
    is_array(value)
}

junit_passed if {
    some edge in all_evidence
    node := edge.node
    object.get(node, "verified", false) == true
    result := predicate(node)
    summary := result.testReport.summary
    to_number(summary.totalTests) > 0
    to_number(summary.totalFailures) == 0
    to_number(summary.totalErrors) == 0
    to_number(summary.totalSkipped) == 0
    to_number(summary.successRate) == 100
}

xray_passed if {
    some edge in all_evidence
    node := edge.node
    object.get(node, "verified", false) == true
    result := predicate(node)
    result.scanner.name == "JFrog Xray"
    result.policyResult == "PASS"
    valid_scan(result.scan)
}

sonar_passed if {
    some edge in all_evidence
    node := edge.node
    object.get(node, "verified", false) == true
    result := predicate(node)
    result.scanner.name == "SonarQube"
    result.policyResult == "PASS"
    result.scanResult == "SUBMITTED"
    result.analysis.projectKey != ""
    result.analysis.ceTaskId != ""
}

default should_allow := false
should_allow if {
    junit_passed
    xray_passed
    sonar_passed
}

allow := {
    "should_allow": should_allow,
    "message": "QA requires verified passing JUnit results, verified passing JFrog Xray scan evidence, and verified SonarQube scan evidence",
}
