# AUTOPLAYBOOK

This playbook is for humans and AI agents that manage self-hosted runners on demand.

## Goal

Use self-hosted runners only when required, keep GitHub-hosted defaults for everything else, and avoid service sprawl.

## Default workflow strategy

Use this in repository workflows:

```yaml
runs-on: ${{ vars.CI_RUNNER && fromJSON(vars.CI_RUNNER) || 'ubuntu-latest' }}
```

- CI_RUNNER unset: GitHub-hosted runner.
- CI_RUNNER set to labels: self-hosted runner.

Example CI_RUNNER values:

```text
["self-hosted","linux","x64"]
["self-hosted","macOS","arm64"]
["self-hosted","windows","x64"]
```

## On-demand runner lifecycle

### 1) Register for one repository

macOS/Linux:

```bash
scripts/bootstrap_runner.sh register --repo owner/repo --prompt-service
```

Windows:

```powershell
.\scripts\bootstrap_runner.ps1 -Action register -Repo owner/repo -PromptService
```

### 2) Run one job and auto-cleanup

Use ephemeral mode when possible:

macOS/Linux:

```bash
scripts/bootstrap_runner.sh register-and-run-once --repo owner/repo
```

Windows:

```powershell
.\scripts\bootstrap_runner.ps1 -Action register-and-run-once -Repo owner/repo
```

Ephemeral runners process one job and then unregister automatically.

### 3) Remove persistent runners when no longer needed

macOS/Linux:

```bash
scripts/bootstrap_runner.sh remove --repo owner/repo
```

Windows:

```powershell
.\scripts\bootstrap_runner.ps1 -Action remove -Repo owner/repo
```

## Agent execution checklist

1. Inspect workflow runner labels requested for target job.
2. If CI_RUNNER is unset, do nothing.
3. If CI_RUNNER targets self-hosted and no runner is online:
4. Choose machine by label compatibility.
5. Register runner using scripts in this repository.
6. Verify online status with GitHub API.
7. Trigger or re-run workflow.
8. Prefer ephemeral mode for single-run tasks.
9. Remove persistent runners after batch completion if not required.

## Verify runner status

```bash
gh api repos/owner/repo/actions/runners --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
```

## Safety and scaling rules

- Do not pre-install services for every repository.
- Use service mode only for high-frequency repositories.
- Prefer ephemeral runners for occasional builds.
- Keep labels predictable and minimal.
- Do not store tokens in files.

## Troubleshooting

- 404 or permission errors: ensure account has repository admin permissions.
- Job queued forever: no runner with matching labels is online.
- Incorrect machine selected: align labels in CI_RUNNER and runner registration.
