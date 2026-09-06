# AppTrust Workshop with GitHub Codespaces

Build and govern a container release from your browser in 75–90 minutes:

```text
HTTP tests → Docker image → Artifactory + Build-info → AppTrust version
  → DEV → signed JUnit, Xray, and SonarQube evidence → QA policy gate → release
```

This workshop follows `jfrog-sample/.github/workflows/apptrust-pipeline.yml` and `apptrust-sample/Dockerfile`: a Node HTTP service on port 3000, application versions, signed evidence, stage promotion, SonarQube quality evidence, and a GitHub Actions release job.

## Learning objectives

| AppTrust capability | Exercise and observable result |
|---|---|
| Application-centric releases | Create a version from a published Docker manifest and inspect its releasables. |
| Signed evidence | Attach real JUnit-format results, Xray scan results, and SonarQube quality gate results; inspect the signature, provider, predicate, subject, and stage. |
| Lifecycle governance | Promote the same version through DEV and QA without rebuilding the image. |
| Policy enforcement | Configure JUnit, Xray, and SonarQube requirements, observe missing-evidence rejection, then attach evidence and retry. |
| Security and auditability | Inspect Xray results and the application timeline, then evaluate the release gate. |

The image contains the official **Log4j API and Core 2.24.1 JARs**:

```text
/app/lib/log4j-api-2.24.1.jar
/app/lib/log4j-core-2.24.1.jar
```

Log4j 2 publishes separate modules, not an official combined `log4j-2.24.1.jar`. The Docker build validates pinned SHA-256 checksums, and the pipeline checks both files before pushing. The hashes were calculated from Maven Central JARs after checking Central's published checksums; this release does not publish `.sha512` sidecars. The Node service does not execute the JARs; they are included for component discovery and governance exercises. Component presence alone does not establish exploitability.

## 1. Instructor prerequisites

Use a JFrog tenant with AppTrust, Evidence, and Xray enabled, and a GitHub repository with Actions and Codespaces available. Defaults are Project `alex`, repository `alex-docker-dev-local`, and CI application `alex-apptrust-workshop`.

1. Ensure the Project and Docker repositories exist. Configure the application's lifecycle with DEV, QA, and a PROD release stage, and map Docker repositories to the stages. Only the DEV repository is passed by the script; target repositories come from platform configuration.
2. Provide a token with Docker push, Build-info, AppTrust application/version creation, promotion, evidence, and release permissions. Automatic lab signing also requires permission to register evidence public keys.
3. Enable Xray indexing and configure the applicable Watch and policies. A CLI scan does not replace a platform release gate.
4. Configure the workshop's **QA entry gate**. The supplied script creates an application-scoped blocking policy that requires verified JUnit, Xray, and SonarQube evidence and validates their result contents:

   ```bash
   JF_SERVER_ID=demo JF_PROJECT=alex APP_KEY=alex-apptrust-workshop \
     bash scripts/configure-qa-gate.sh
   ```

   The custom rule validates these JUnit fields:

   ```text
   testReport.summary.totalTests > 0
   testReport.summary.totalFailures == 0
   testReport.summary.totalErrors == 0
   testReport.summary.totalSkipped == 0
   testReport.summary.successRate == 100
   ```

   It also requires verified `https://jfrog.com/evidence/security-scan/v1` evidence from JFrog Xray with `policyResult: PASS` and an embedded JSON scan report. SonarQube evidence must use `https://sonarsource.com/evidence/quality-gate/v1`, include `policyResult: PASS`, and show quality gate status `OK`. The script is idempotent by resource name; review existing resources before changing its names or scope.

5. Configure release-gate security requirements separately. Findings depend on the current Xray database and policy; do not assume Log4j 2.24.1 always passes or triggers a particular CVE.
6. If human approval is required, configure required reviewers under **GitHub Settings → Environments → production**. A YAML environment name alone does not enable approval. Without reviewers, release proceeds automatically after its dependencies pass.

The workflow does not create or weaken platform policies. Missing-evidence rejection requires a matching blocking policy. If promotion succeeds without evidence, inspect policy configuration rather than treating that as a successful negative test.

## 2. Open a Codespace — 10 minutes

Select **Code → Codespaces → Create codespace on main**. The root [devcontainer configuration](.devcontainer/devcontainer.json) provides Node 22, Docker-in-Docker, GitHub CLI, and SSH for remote verification. Its post-create script installs JFrog CLI 2.122.0.

Configure `JF_ACCESS_TOKEN` as a **Codespaces secret** and grant access to this repository. Actions and Codespaces secrets are separate settings.

```bash
cp .env.example .env
# Edit .env: set your tenant URL and a unique learner APP_KEY and APP_VERSION.
export PATH="$HOME/.local/bin:$PATH"
bash scripts/workshop.sh login
bash scripts/workshop.sh init
npm start
```

Open port 3000 from the Ports panel. `/healthz` returns `{"status":"ok"}`; `/` returns the service name and version. Keep the forwarded port private. Press Ctrl+C before continuing.

`JFROG_URL` is accepted as an alias for `JF_URL`. If CLI is already configured for this tenant, set `JF_SERVER_ID` accordingly and skip `login`. `init` creates the application or accepts a specific “already exists” response; other creation failures stop the script.

## 3. Build and create an application version — 15 minutes

```bash
bash scripts/workshop.sh build
bash scripts/workshop.sh version
```

The build runs three real HTTP tests and writes `reports/junit.xml` and `reports/junit.json`. It then builds the image, checks both JARs, pushes the image, and publishes Build-info with Git metadata. The image reference is:

```text
<tenant-host>/<DEV-repository>/<APP_KEY>:<APP_VERSION>
```

This example assumes Artifactory repository-path Docker routing. Adjust the reference for tenants using other routing methods.

In Artifactory, inspect the manifest, digest, and Build-info. In AppTrust, inspect the version's releasables. The version is created from the manifest and enters DEV; subsequent promotion and release do not rebuild it. Use a new numeric `x.y.z` version for each new build rather than overwriting a published version.

## 4. Signed JUnit evidence and a negative exercise — 20 minutes

With the instructor's blocking QA policy enabled, try promotion before attaching evidence:

```bash
bash scripts/workshop.sh qa
```

Expect a nonzero exit and a missing-evidence explanation in AppTrust Evaluation / Timeline. If it succeeds, stop this negative exercise and fix the policy binding or warning-only action.

Generate a lab key, register its public key, and attach evidence:

```bash
# .env defines EVIDENCE_KEY and EVIDENCE_KEY_ALIAS.
# Give each learner/version a unique alias before generating a key.
bash scripts/workshop.sh keygen
bash scripts/workshop.sh evidence
bash scripts/workshop.sh scan
bash scripts/workshop.sh xray-evidence
# Run the SonarQube scan first in GitHub Actions, or run sonar-scanner locally.
bash scripts/workshop.sh sonar-evidence
bash scripts/workshop.sh qa
```

To reuse an existing trusted private key, store it at `EVIDENCE_KEY` with mode 600, configure its alias, and skip `keygen`. Never commit `.keys/` or private keys.

The tests use Node's built-in test runner and its **JUnit XML reporter**, not the Java JUnit engine. The converter reads actual cases and records the XML SHA-256. Empty reports, failed/error/skipped cases, and malformed XML prevent passing evidence. The Xray predicate is only produced after `jf docker scan --fail=true` succeeds and its JSON parses. The SonarQube predicate is only produced after the scanner writes `.scannerwork/report-task.txt` and the Sonar API reports quality gate status `OK`. All signed evidence records target the current application version and are attached in DEV before QA evaluation.

Inspect the evidence's provider, predicate, signature identity, subject, and stage. Change a response expectation in `test/server.test.js` and run `bash scripts/test.sh` to observe a real failure. Restore it afterward. Failed tests prevent image publication and do not reuse an old evidence JSON file.

## 5. Scan and release — 15 minutes

```bash
# Inspect reports/xray.json, reports/xray-evidence.json, and platform findings.
bash scripts/workshop.sh release
```

In Xray, locate `log4j-api` and `log4j-core` version 2.24.1. Investigate service failures or policy violations. The script preserves nonzero scan status and does not manufacture passing security evidence from text matching.

The release operation enters the official release stage and evaluates its gate. Ordinary promotion is not a substitute; see [JFrog's release documentation](https://docs.jfrog.com/governance/docs/release-an-application-version). Inspect the final status, evaluation, timeline, target repository, and image digest.

Manual release from Codespaces does not pass through GitHub approval. Use it only for the lab; production permissions should belong to the intended release identity.

## 6. Run GitHub Actions — 15 minutes

The [workflow](.github/workflows/apptrust-pipeline.yml) reuses the Codespaces scripts.

| Setting | Required | Purpose / default |
|---|---|---|
| Variable `JFROG_URL` | Yes | Tenant root URL, such as `https://demo.jfrogchina.com` |
| Secret `JF_ACCESS_TOKEN` | Yes | JFrog token |
| Variable `APPTRUST_PROJECT` | No | `alex` |
| Variable `APPTRUST_DOCKER_REPO_DEV` | No | `alex-docker-dev-local` |
| Variable `APPTRUST_APP_KEY` | No | `alex-apptrust-workshop` |
| Secret `SONAR_TOKEN` | Yes | SonarQube or SonarQube Cloud token used by the scan and quality gate evidence |
| Variable `SONAR_HOST_URL` | No | `https://sonarcloud.io`; set this for self-managed SonarQube |
| Secret `EVIDENCE_PRIVATE_KEY` | No | Existing trusted PEM key; otherwise generate a per-run lab key |
| Variable `EVIDENCE_KEY_ALIAS` | With an existing key | Registered alias; otherwise a unique run/attempt alias is generated |

Only URL and token are needed for the default lab when the existing Project, repositories, lifecycle, and permissions meet the prerequisites. Automatic signing follows the reference pipeline: register a per-run public key, sign evidence, then remove the private key. Retain public keys for signature verification under the instructor's retention policy. Production should use a controlled signing identity.

- **Pull requests:** tests only, without publishing credentials.
- **Main push or manual run on main:** tests → application setup → build/push → Build-info → SonarQube scan → version → DEV → signed JUnit → signed Xray → signed SonarQube quality gate → QA gate → production environment → release.
- Default version: `1.0.<run_number>`. Manual runs accept a new numeric SemVer. Rerunning a published version can conflict; start a new run instead.
- Select `omit_junit=true` or `omit_sonar=true` for a negative exercise. A configured QA gate should reject the run. If the platform unexpectedly accepts it, the workflow fails explicitly with a missing-policy diagnostic. Negative runs never execute release.
- Download `junit-tests` and `release-reports` for XML, predicate, digest, SonarQube, and scan logs. Private keys are excluded.

## Verification and cleanup

```bash
bash scripts/test.sh
python3 -m unittest discover -s tests -v
bash -n scripts/*.sh
docker build -t apptrust-workshop:local .
bash scripts/smoke-image.sh apptrust-workshop:local
```

Acceptance: three HTTP tests pass; both JARs exist; the application version shows signed JUnit, Xray, and SonarQube evidence; the configured policy rejects missing evidence; the corrected version reaches QA and release; the Docker digest is unchanged across stages.

Troubleshooting:

- Docker unavailable: rebuild the Codespace and inspect Docker feature logs.
- Registry connection errors: check Docker Hub, Alpine repositories, Maven Central, and JFrog CLI release connectivity.
- 401/403: check the same tenant's token and permissions; do not switch tenants as a workaround.
- Evidence target not ready: inspect version creation status, then retry attachment after completion.
- Unexpected promotion success: inspect policy binding, source stage, and blocking action.
- Release waiting in GitHub: inspect production environment approval requirements.

Stop the Codespace when finished and delete it when no longer needed. Remove local private keys and revoke temporary tokens as instructed. Retain platform artifacts, evidence, and public keys under the organization's audit policy.
