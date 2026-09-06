# JFrog AppTrust Workshop with GitHub Codespaces

This workshop is written for JFrog customers who want to see how AppTrust governs a container release with signed evidence and lifecycle gates. You will build a small Node.js service, publish its Docker image to Artifactory, attach JUnit, JFrog Xray, and SonarQube evidence, promote the version through DEV and QA, and release it.

The workshop takes about 75 to 90 minutes. Every section has a checkpoint so participants can verify progress before moving on.

```text
Test -> Build image -> Push to Artifactory -> Create AppTrust version
  -> Promote to DEV -> Attach signed evidence -> Pass QA gate -> Release
```

The Docker image includes these files for Xray and AppTrust inspection:

```text
/app/lib/log4j-api-2.24.1.jar
/app/lib/log4j-core-2.24.1.jar
```

Log4j 2.24.1 is included as application content for component discovery and governance exercises. The Node.js service does not execute the JARs.

## What Participants Will Learn

| AppTrust capability | What participants do | What they should see |
|---|---|---|
| Application versions | Create an AppTrust version from a Docker manifest. | One version with releasables linked to the pushed image. |
| Signed evidence | Attach JUnit, Xray, and SonarQube scan evidence. | Verified evidence records on the application version. |
| Lifecycle governance | Promote the same version from DEV to QA. | Promotion copies the same release content without rebuilding. |
| Policy gates | Require evidence before QA entry. | Missing evidence is rejected; complete evidence passes. |
| Release audit trail | Release the governed version. | Timeline shows build, evidence, promotion, and release events. |

## Environment Used by This Lab

The default configuration is ready for the instructor environment used by this repository:

| Setting | Default |
|---|---|
| JFrog Project | `alex` |
| DEV Docker repository | `alex-docker-dev-local` |
| AppTrust application | `alex-apptrust-workshop` |
| DEV stage | `DEV` |
| QA stage | `QA` |
| SonarQube Cloud organization | `alexwang66` |
| SonarQube project key | `alexwang66_apptrust-workshop` |

If you run this workshop in another tenant, update `.env`, GitHub variables, and `sonar-project.properties` before running the pipeline.

## Instructor Setup

Complete this once before participants start.

1. Verify that the JFrog tenant has AppTrust, Evidence, Artifactory, and Xray enabled.
2. Verify that Project `alex` and Docker repository `alex-docker-dev-local` exist, or update the defaults.
3. Verify that the AppTrust lifecycle has `DEV`, `QA`, and a release stage such as `PROD`.
4. Configure GitHub repository variables and secrets:

| Name | Type | Required | Purpose |
|---|---|---|---|
| `JFROG_URL` | Variable | Yes | JFrog tenant root URL, for example `https://demo.jfrogchina.com` |
| `APPTRUST_PROJECT` | Variable | No | Defaults to `alex` |
| `APPTRUST_DOCKER_REPO_DEV` | Variable | No | Defaults to `alex-docker-dev-local` |
| `APPTRUST_APP_KEY` | Variable | No | Defaults to `alex-apptrust-workshop` |
| `SONAR_HOST_URL` | Variable | No | Defaults to `https://sonarcloud.io` |
| `JF_ACCESS_TOKEN` | Secret | Yes | Token with Docker push, Build-info, AppTrust, Evidence, and release permissions |
| `SONAR_TOKEN` | Secret | Yes | Token used by the SonarQube scan |
| `EVIDENCE_PRIVATE_KEY` | Secret | No | Existing trusted PEM key; otherwise the pipeline creates a per-run lab key |
| `EVIDENCE_KEY_ALIAS` | Variable | With existing key | Registered evidence key alias |

5. Create or update the QA entry gate:

```bash
JF_SERVER_ID=demo JF_PROJECT=alex APP_KEY=alex-apptrust-workshop \
  bash scripts/configure-qa-gate.sh
```

Checkpoint:

- The command prints `QA gate ready`.
- The policy name is `AppTrust workshop QA evidence gate with Sonar v2`.
- The policy is enabled, blocking, scoped to `alex-apptrust-workshop`, and attached to the QA entry gate.

The QA gate requires three verified evidence records on the AppTrust version:

| Evidence | Provider | Predicate check |
|---|---|---|
| JUnit | `junit` | `totalTests > 0`, `failures = 0`, `errors = 0`, `skipped = 0`, `successRate = 100` |
| Xray | `jfrog-xray` | scanner is `JFrog Xray`, `policyResult = PASS`, scan JSON is present |
| SonarQube | `sonarqube` | scanner is `SonarQube`, `policyResult = PASS`, scan submission has `projectKey` and `ceTaskId` |

## Participant Step 1: Open the Codespace

Open GitHub and select **Code -> Codespaces -> Create codespace on main**.

The dev container installs Node.js 22, Docker-in-Docker, GitHub CLI, SSH, Python, `jq`, and JFrog CLI 2.122.0.

Run:

```bash
node --version
docker version
jf --version
python3 --version
jq --version
```

Checkpoint:

- `node --version` starts with `v22`.
- `docker version` returns both client and server information.
- `jf --version` returns JFrog CLI 2.122.0 or newer.
- `jq --version` prints a version.

## Participant Step 2: Configure Local Lab Variables

Create a local `.env` file:

```bash
cp .env.example .env
```

Edit `.env` and set:

```bash
JF_URL=https://YOUR_TENANT
JF_PROJECT=alex
DOCKER_REPO_DEV=alex-docker-dev-local
APP_KEY=alex-workshop-yourname
APP_VERSION=1.0.1
JF_SERVER_ID=demo
STAGE_DEV=DEV
STAGE_QA=QA
EVIDENCE_KEY=.keys/evidence.key
EVIDENCE_KEY_ALIAS=workshop-yourname-1
```

Configure `JF_ACCESS_TOKEN` and `SONAR_TOKEN` as Codespaces secrets. Do not put token values in `.env`.

Checkpoint:

- `.env` exists locally.
- `.env` is ignored by git.
- `APP_KEY` is lowercase and unique for the participant.
- `APP_VERSION` is a numeric SemVer such as `1.0.1`.

## Participant Step 3: Connect to JFrog and Create the App

Run:

```bash
export PATH="$HOME/.local/bin:$PATH"
bash scripts/workshop.sh login
bash scripts/workshop.sh init
```

Checkpoint:

- `login` returns a successful AppTrust ping.
- `init` either creates the AppTrust application or prints `Application already exists`.
- In the JFrog UI, the application key appears under AppTrust applications.

## Participant Step 4: Run the Service Locally

Start the service:

```bash
npm start
```

Open port 3000 from the Codespaces **Ports** tab and test:

```bash
curl http://127.0.0.1:3000/healthz
curl http://127.0.0.1:3000/
```

Checkpoint:

- `/healthz` returns `{"status":"ok"}`.
- `/` returns the service name and version.
- The forwarded port remains private.

Stop the service with `Ctrl+C`.

## Participant Step 5: Run Tests and Generate JUnit Evidence Data

Run:

```bash
bash scripts/test.sh
python3 -m unittest discover -s tests -v
```

Checkpoint:

- The HTTP tests pass.
- `reports/junit.xml` exists.
- `reports/junit.json` exists.
- `reports/junit.json` shows `totalTests: 3`, `totalFailures: 0`, `totalErrors: 0`, and `successRate: 100`.

## Participant Step 6: Build, Validate, and Push the Docker Image

Run:

```bash
bash scripts/workshop.sh build
```

Checkpoint:

- Docker build succeeds.
- The image contains both Log4j 2.24.1 JARs under `/app/lib`.
- `scripts/smoke-image.sh` passes.
- The image is pushed to Artifactory.
- Build-info is published.
- `reports/image-digests.json` exists.

In Artifactory, inspect:

- Repository: `alex-docker-dev-local`
- Image path: `<APP_KEY>:<APP_VERSION>`
- Build name: `<APP_KEY>-build`
- Build number: `<APP_VERSION>`

## Participant Step 7: Create and Promote the AppTrust Version to DEV

Run:

```bash
bash scripts/workshop.sh version
```

Checkpoint:

- AppTrust version `<APP_VERSION>` exists.
- The version has releasables linked to the Docker manifest.
- The version is in the `DEV` stage.
- No rebuild occurs during promotion.

## Participant Step 8: Observe the QA Gate Blocking Missing Evidence

Run this before attaching evidence:

```bash
bash scripts/workshop.sh qa
```

Expected result:

- The command fails.
- The response says the copy promotion from `DEV` to `QA` failed due to policy violations.
- The QA entry gate decision is `fail`.

Checkpoint in the JFrog UI:

- Open the AppTrust version.
- Open the evaluation or timeline entry for the failed QA promotion.
- Confirm that the blocking policy rejected the version because required evidence was missing.

## Participant Step 9: Attach Signed JUnit Evidence

Generate and register a lab signing key:

```bash
bash scripts/workshop.sh keygen
```

Attach the JUnit evidence:

```bash
bash scripts/workshop.sh evidence
```

Checkpoint:

- The public key is registered in JFrog Evidence.
- The private key remains local under `.keys/`.
- The AppTrust version shows verified evidence from provider `junit`.
- The predicate contains the JUnit test summary and the SHA-256 of `reports/junit.xml`.

## Participant Step 10: Run Xray and Attach Xray Evidence

Run:

```bash
bash scripts/workshop.sh scan
bash scripts/workshop.sh xray-evidence
```

Checkpoint:

- `reports/xray.json` exists.
- `reports/xray-evidence.json` exists.
- The AppTrust version shows verified evidence from provider `jfrog-xray`.
- The predicate contains scanner `JFrog Xray`, `policyResult: PASS`, and the image reference.
- In Xray or Artifactory, locate `log4j-api` and `log4j-core` version 2.24.1.

## Participant Step 11: Run SonarQube and Attach SonarQube Evidence

The GitHub Actions pipeline runs SonarQube automatically. For a local Codespaces run, install and run `sonar-scanner` if your instructor has provided local SonarQube access.

After a successful SonarQube scan writes `.scannerwork/report-task.txt`, run:

```bash
bash scripts/workshop.sh sonar-evidence
```

Checkpoint:

- `.scannerwork/report-task.txt` exists.
- `reports/sonar-report-task.txt` exists.
- `reports/sonar-evidence.json` exists.
- The AppTrust version shows verified evidence from provider `sonarqube`.
- The predicate contains scanner `SonarQube`, `scanResult: SUBMITTED`, `projectKey`, and `ceTaskId`.

## Participant Step 12: Promote to QA

Run:

```bash
bash scripts/workshop.sh qa
```

Checkpoint:

- The promotion succeeds.
- The QA entry gate decision is `pass`.
- The evaluation shows the JUnit, Xray, and SonarQube evidence requirements passed.
- The version is now in the `QA` stage.

## Participant Step 13: Release the Version

Run:

```bash
bash scripts/workshop.sh release
```

Checkpoint:

- The release command succeeds.
- The version enters the configured release stage.
- The AppTrust timeline shows release activity.
- The release uses the same Docker digest that was promoted through DEV and QA.

Manual release from Codespaces does not use GitHub environment approval. For production workflows, configure required reviewers under **GitHub Settings -> Environments -> production**.

## GitHub Actions Path

The workflow in `.github/workflows/apptrust-pipeline.yml` runs the same workshop flow on `main`.

Normal run:

```text
test -> build-and-govern -> release
```

The `build-and-govern` job performs:

```text
login -> init -> build -> SonarQube scan -> version -> JUnit evidence
  -> Xray scan -> Xray evidence -> SonarQube evidence -> QA promotion
```

Checkpoint after a successful run:

- GitHub Actions run conclusion is `success`.
- `test`, `build-and-govern`, and `release` jobs are all green.
- AppTrust version has verified JUnit, Xray, and SonarQube evidence.
- QA promotion has `decision: pass`.
- Release job succeeds.

Negative exercises:

| Input | Expected result |
|---|---|
| `omit_junit=true` | QA gate rejects the version; release is skipped. |
| `omit_sonar=true` | QA gate rejects the version; release is skipped. |

If a negative run reaches QA successfully, the workflow fails with a policy diagnostic. Fix the policy binding before using that exercise with participants.

## Quick Verification Commands

Run these before a workshop or after editing the repo:

```bash
bash scripts/test.sh
python3 -m unittest discover -s tests -v
bash -n scripts/*.sh
python3 -c "import yaml; from pathlib import Path; [yaml.safe_load(p.read_text()) for p in Path('.github/workflows').glob('*.yml')]"
docker build -t apptrust-workshop:local .
bash scripts/smoke-image.sh apptrust-workshop:local
```

Checkpoint:

- Three HTTP tests pass.
- Python converter tests pass.
- Shell scripts parse.
- GitHub workflow YAML parses.
- Docker build and smoke test pass.

## Troubleshooting

| Symptom | Check |
|---|---|
| Docker is unavailable | Rebuild the Codespace and inspect Docker-in-Docker startup logs. |
| `jf` is missing | Run `bash scripts/bootstrap.sh` and reopen the shell. |
| `401` or `403` from JFrog | Check the token belongs to the same tenant and has AppTrust, Evidence, Docker, Build-info, and release permissions. |
| App creation fails | Check `APP_KEY`, project membership, and application permissions. |
| Image push fails | Check Docker repository permissions and repository path routing. |
| Xray scan fails | Check Xray indexing, watches, policies, and CLI scan output in `reports/xray.json`. |
| SonarQube scan fails | Check `SONAR_TOKEN`, `SONAR_HOST_URL`, `sonar.organization`, and `sonar.projectKey`. |
| Evidence upload fails | Confirm the AppTrust version exists and the signing key alias is registered. |
| QA promotion unexpectedly passes without evidence | Check the QA entry policy scope, mode, action, and application key. |
| Release waits in GitHub | Check required reviewers in the `production` environment. |

## Cleanup

At the end of the workshop:

```bash
rm -rf .keys reports .scannerwork
```

Stop or delete the Codespace when finished. Retain JFrog evidence, release history, and public signing keys according to your organization's audit policy.
