package curation.policies
import rego.v1

release := input.data

release_evidence := [e | some e in object.get(release, "evidenceConnection", {"edges": []}).edges]

junit_passed if {
    some edge in release_evidence
    node := edge.node
    object.get(node, "verified", false) == true
    summary := node.predicate.testReport.summary
    summary.totalTests > 0
    summary.totalFailures == 0
    summary.totalErrors == 0
    summary.totalSkipped == 0
    summary.successRate == 100
}

xray_passed if {
    some edge in release_evidence
    node := edge.node
    object.get(node, "verified", false) == true
    result := node.predicate
    result.scanner.name == "JFrog Xray"
    result.policyResult == "PASS"
    is_object(result.scan)
}

sonar_passed if {
    some edge in release_evidence
    node := edge.node
    object.get(node, "verified", false) == true
    result := node.predicate
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
