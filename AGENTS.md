# Start here

The tool-neutral entry point for anyone -- person or agent -- changing this repository. The
detailed rules live in three files:

- [`CLAUDE.md`](CLAUDE.md) -- what the module is, when the derived reports must be
  regenerated, and what to run before pushing.
- [`Tests/CLAUDE.md`](Tests/CLAUDE.md) -- writing and running the Pester tests, the
  two-edition rule, and the coverage baseline in `Tests/coverage-baseline.psd1`.
- [`.github/workflows/CLAUDE.md`](.github/workflows/CLAUDE.md) -- authoring the GitHub
  Actions workflows.

## What CI checks on a pull request

| Workflow | What it checks | Fails the PR? |
|---|---|---|
| `cross-platform-tests.yml` | Pester on Windows PowerShell 5.1 and on PowerShell 7 (Windows, Linux, macOS), the coverage baseline, and PSScriptAnalyzer; on the 5.1 leg, a Windows PowerShell 5.1 parse and compatibility check (`tools/Test-PfbPs51Compat.ps1`) | Yes |
| `verify-derived-artifacts.yml` | Every committed artifact in `Data/` and `Reports/` matches a regeneration from the branch (runs when an input changes) | Yes |
| `verify-workflows.yml` | actionlint over `.github/workflows/` (runs when `.github/` changes) | Yes |
| `verify-closing-keywords.yml` | Every issue the PR body or a commit references after a closing keyword has its own keyword | Yes |
| `verify-wire-exemption.yml` | Whether the diff can change a request the module sends or a response it parses | No -- informational |

"Fails the PR" means the check goes red. None is a required status check; merging is the
maintainer's decision.

Scheduled, not on pull requests: `update-api-capability-map.yml`,
`verify-agent-ready-briefs.yml` and `report-action-pins.yml`.

## Scripts you can run locally

Under PowerShell 7 (`pwsh`); only the module itself has to run on Windows PowerShell 5.1.

- `scripts/Assert-PfbDerivedArtifacts.ps1` -- the derived-artifact check CI runs.
- `tools/Test-PfbWireExemption.ps1 -BaseRef origin/main` -- whether your branch can change
  what goes on the wire. Exit 0 exempt, 1 not, 2 undecided. Prints a basis line for the PR
  body when exempt.
- `tools/Test-PfbClosingKeywords.ps1 -Text <your PR body>` -- the closing-keyword check, with
  the corrected form for each finding.
- `powershell.exe -File tools/Test-PfbPs51Compat.ps1 -All` -- the Windows PowerShell 5.1
  parse and compatibility check. Run it under Windows PowerShell 5.1, not pwsh.
