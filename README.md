# GitHub Runner

Reusable scripts and playbooks for on-demand GitHub Actions self-hosted runners across personal repositories.

This project is designed for people who do not use a GitHub organization runner pool but still want sane automation.

## What this solves

- Register a self-hosted runner for one repository quickly.
- Support macOS, Linux, and Windows hosts.
- Avoid leaving hundreds of runner services running.
- Let CI use GitHub-hosted by default and self-hosted only when needed.

## Repository layout

- scripts/bootstrap_runner.sh: macOS/Linux bootstrap
- scripts/bootstrap_runner.ps1: Windows bootstrap
- docs/AUTOPLAYBOOK.md: agent and operator runbook

## Quick start

macOS/Linux register and install service:

```bash
scripts/bootstrap_runner.sh register --repo owner/repo --service
```

macOS/Linux ephemeral run (one job then exit and unregister):

```bash
scripts/bootstrap_runner.sh register-and-run-once --repo owner/repo
```

Windows register and install service:

```powershell
.\scripts\bootstrap_runner.ps1 -Action register -Repo owner/repo -RunAsService
```

Windows ephemeral run:

```powershell
.\scripts\bootstrap_runner.ps1 -Action register-and-run-once -Repo owner/repo
```

Remove runner registration:

```bash
scripts/bootstrap_runner.sh remove --repo owner/repo
```

```powershell
.\scripts\bootstrap_runner.ps1 -Action remove -Repo owner/repo
```

## Consuming from another repository

Use as a git submodule:

```bash
git submodule add https://github.com/keithjasper83/GitHub-Runner.git tooling/github-runner
git commit -m "Add GitHub Runner dependency"
```

Then call scripts from the submodule path.

## Recommended CI pattern

In each repository workflow, keep GitHub-hosted as default:

```yaml
runs-on: ${{ vars.CI_RUNNER && fromJSON(vars.CI_RUNNER) || 'ubuntu-latest' }}
```

Use repository variable CI_RUNNER only when you need self-hosted labels, for example:

```text
["self-hosted","linux","x64"]
```

## Security notes

- Scripts do not store long-lived registration tokens.
- Tokens are requested just-in-time from GitHub API through gh CLI.
- Repository admin access is required to register or remove runners.

## License

Apache-2.0
