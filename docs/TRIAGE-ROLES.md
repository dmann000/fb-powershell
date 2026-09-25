# Triage roles and the issue state machine

The labels on this repo's issues are a **machine interface**, not decoration. A scheduled
worker decides what to pick up by reading them, and a reconciler decides what not to file
again. This document pins the vocabulary so that meaning does not drift.

If you are applying labels by hand, the short version is: **exactly one label from each of
the five single-valued axes, on every open issue.**

## The five axes

| Axis | Values | Single-valued |
|---|---|---|
| `status:` | the state machine below | yes |
| `priority:` | `P0` `P1` `P2` `P3` | yes |
| `size:` | `S` `M` `L` | yes |
| `area:` | the noun-families below | yes |
| `source:` | `drift` `human` `livetest` | yes |
| `needs:` | `live-test` | no — a flag, present or absent |

The stock GitHub labels (`bug`, `enhancement`, `documentation`, …) still exist and are
harmless, but nothing reads them. Do not use them to express state.

## `status:` — the state machine

| Label | Meaning |
|---|---|
| `status:triage` | Unassessed. The honest default for a new issue. |
| `status:needs-design` | Understood, but the *approach* is not settled. |
| `status:design-approved` | The approach is decided and recorded on the issue. Implementation may start. |
| `status:agent-ready` | An **agent brief** is attached. See below — this one is a promise, not an opinion. |
| `status:in-progress` | Work is underway on a branch. |
| `status:needs-review` | A PR is open and waiting on human review. |
| `status:blocked` | Cannot proceed. **The blocker must be named in a comment.** |
| `status:human-only` | Requires human judgment or access. An agent must not pick it up even if it looks tractable. |
| `status:resolved-upstream` | Set by `tools/New-PfbDriftIssue.ps1` when none of a drift issue's findings are reported any more. A person confirms and closes it; tooling never closes an issue. |

Normal flow:

```
triage -> needs-design -> design-approved -> agent-ready -> in-progress -> needs-review -> (closed)
```

Legal departures from it:

- Any state may move to `blocked` or `human-only`, and back again when the blocker clears.
- `triage` may go straight to `design-approved` when the approach was never in question.
- `agent-ready` may fall back to `triage` or `needs-design`. That is a **success**, not a
  regression: it means someone tried to write the brief and found the scope unsettled.
  Better discovered by a person than by a worker burning an unattended run.
- Anything may close. A closing *reason* carries meaning here — see below.
- `tools/New-PfbDriftIssue.ps1` moves an issue from any state to `resolved-upstream` when
  all of its findings stop being reported, and from `resolved-upstream` back to `triage`
  whenever it has a finding that is still reported. It checks this on every run, so it
  also puts back a label that disagrees with the findings. It **replaces** the current
  `status:` label rather than adding a second one, so the one-per-axis invariant holds,
  and its comment names the label it replaced.

### Two rules that exist because a machine reads this

**`status:triage` is not a scoring input.** It means "nobody has assessed this", not "low
priority" and certainly not "ready". Any ranking or queue-popping logic must treat it as
absent from the queue. Twenty of the forty-three issues open when this file was written
were at `status:triage`; a scorer that read them as workable would be wrong about half the
backlog.

**`status:agent-ready` means a brief is attached.** The label points at a contract — see
[AGENT-BRIEF.md](AGENT-BRIEF.md). It is not a judgement that the issue looks small or
tractable. An issue with no brief does not carry this label, however obvious it seems: an
unattended worker reads the brief, not the issue title, and an issue written for a human
who already knows the codebase is not a specification.

### Closing reasons are part of the vocabulary

There is deliberately **no `wontfix` state**. GitHub's own closing reasons are finer:

- **`completed`** — the work was done.
- **`not planned`** — fits an issue that proposed no change, or one whose premise was
  false. It misrepresents an issue describing a fix we *want* but cannot make yet; those
  stay **open** with `status:blocked` and the blocker named.
- **`duplicate`** — say which issue it duplicates.

When an issue is closed because the request itself was declined or its premise was wrong,
record it in [`docs/settled/`](settled/README.md) so it does not come back as a fresh
finding.

## `priority:`

| Label | Meaning |
|---|---|
| `priority:P0` | Can damage an array, or is silently wrong on the wire today. |
| `priority:P1` | Wrong on the wire, or the tooling is blind in a way that lets P0s recur. |
| `priority:P2` | A real gap with no active harm. The default for net-new coverage. |
| `priority:P3` | Maintenance, release, ergonomics. Safe to leave. |

Priority is about **harm**, not effort or breadth. A wide refactor that hurts nobody is
`P2` with `size:L`, not `P1`.

## `size:`

| Label | Meaning |
|---|---|
| `size:S` | One sitting. Single file or a mechanical change. |
| `size:M` | A day. Several files, one coherent change. |
| `size:L` | Multi-PR. Needs a plan before it needs code. |

## `area:`

| Label | Covers |
|---|---|
| `area:wire-contract` | What a shipped cmdlet actually sends: dead keys, selectors, missing required keys, identifier rules. |
| `area:capability-map` | `Data/PfbCapabilityMap.json`, its generator, and `Assert-PfbApiCapability`. |
| `area:drift-report` | The drift and coverage reports, and the scanners that produce them. |
| `area:fusion` | Fleet, realm, `context_names`, and everything `contextScope` touches. |
| `area:cmdlet-coverage` | New cmdlets for endpoints the module does not yet reach. |
| `area:core-runtime` | `Invoke-PfbApiRequest`, result shaping, error handling, pipeline behaviour. |
| `area:auth` | `Connect-PfbArray`, session lifecycle, tokens and credentials. |
| `area:ci` | Workflows, gates, test scoping and test economics. |
| `area:release` | Publishing, versioning, and fork synchronisation. |

Add a family when one genuinely does not fit; do not stretch `area:core-runtime` into a
catch-all. `area:wire-contract` exists precisely because folding the repo's largest defect
class into `core-runtime` made the biggest bucket the least legible.

## `source:`

Where the finding came from. This is what lets automated issue-filing avoid duplicating
itself.

| Label | Meaning |
|---|---|
| `source:drift` | Opened from a drift-report or gate finding, by tooling. |
| `source:human` | Opened by a person, from observation or field feedback. |
| `source:livetest` | Opened from evidence measured against a real array. |

`source:drift` is also a trust anchor. `tools/New-PfbDriftIssue.ps1` reads the machine
block at the end of an issue body only on an issue carrying this label, because anyone
can write an issue body but only collaborators can apply labels. Do not remove the label
from an issue that carries such a block: the reconciler would stop seeing the issue, and
file its findings again as new.

## `needs:live-test`

The issue cannot be closed on mocked tests alone; it needs verification against a real
array. Orthogonal to everything else — a `status:blocked` issue can still carry it.

## Checking the invariant

Every open issue should carry exactly one label from each single-valued axis. This is
worth asserting rather than assuming, because the failure is silent: a missing `status:`
makes an issue invisible to the queue, and two of them make its state ambiguous.

```powershell
$all = gh issue list --state open --limit 200 --json number,labels | ConvertFrom-Json
foreach ($axis in 'status','priority','size','area','source') {
    $bad = @($all | Where-Object {
        @($_.labels.name | Where-Object { $_ -like "${axis}:*" }).Count -ne 1
    })
    "{0,-9} {1}/{2} ok   offenders: {3}" -f $axis, ($all.Count - $bad.Count), $all.Count, (($bad.number) -join ',')
}
```

Issues filed by the drift reconciler arrive with `status:triage`, `source:drift`, one
`area:` and `needs:live-test`, and deliberately without `priority:` or `size:`:
assigning those is triage, and `status:triage` says nobody has done it yet. The check
above lists them until someone does, which is the intended signal.

## A note on canonical names

Other tooling and published triage workflows use unnamespaced role names — `needs-triage`,
`ready-for-agent`, `ready-for-human`, `wontfix`. The mapping onto this repo:

| Canonical role | Here |
|---|---|
| `needs-triage` | `status:triage` |
| `ready-for-agent` | `status:agent-ready` |
| `ready-for-human` | `status:human-only` |
| `wontfix` | *not implemented* — use a closing reason plus `docs/settled/` |
| `needs-info` | *not implemented* — this repo has no external reporter loop |
