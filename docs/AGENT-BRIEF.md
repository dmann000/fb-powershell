# Writing agent briefs

An **agent brief** is a structured comment posted on an issue when it moves to
`status:agent-ready`. It is the authoritative specification the implementer works from.
The issue body and its discussion are context; the brief is the contract.

It exists because an issue here is usually written *for a reader who already knows the
codebase* — it argues that something is wrong, with evidence. An implementer needs
something different: what to change, how to know when it is done, and what not to touch.

If you cannot write the brief, the issue is not `status:agent-ready`. Move it back to
`status:triage` or `status:needs-design` and say in a comment what is unresolved. That is
the intended outcome in that case, not a failure.

## Principles

### Durability over precision

An issue can sit at `agent-ready` for weeks while the tree moves under it.

- **Do** describe behaviour, wire keys, parameter contracts and cmdlet names.
- **Don't** cite file paths or line numbers. They go stale, and the implementer is going
  to open the file anyway.
- **Don't** pin a count in prose. A count is a claim with a delay fuse: state the
  property and let an assertion derive the membership. This repo has paid for that lesson
  more than once — a fix for a wrong number has twice introduced another wrong number.

### Behavioural, not procedural

Say what the system should do, not how to edit it. The implementer explores fresh and
makes its own structural decisions.

- **Good:** "`-LocalDirectoryService` is sent as the `local_directory_service_names` query key."
- **Bad:** "Add a line to the `queryParams` hashtable in the `process` block."

### Acceptance criteria must be checkable

Each one independently verifiable, by running something or reading something. "Works
correctly" is not a criterion.

### Explicit scope boundaries

State what must *not* change. Without this, an implementer folds in the adjacent defect
it noticed, and a three-line fix arrives as a sixty-line diff that reads as scope creep.

## Two sections this repo requires

Beyond the usual template, a brief here carries two things that exist because of gates a
generic brief has no reason to know about.

### `Verification:`

State one of:

- `live-verified <date>, <what was run>` — the claim was reproduced against a real array.
- `not verified — <why>` — say what would verify it.
- `n/a — cannot reach the wire` — the change has no request path (tooling, tests, docs).

A confirmed reproduction makes a far stronger brief, and finding that the claim does *not*
reproduce is the cheapest possible outcome. If the issue carries `needs:live-test`, name
the verification the fix itself will need.

Describe the array by capability, not by lab name — "an AD-joined FlashBlade at REST 2.26"
rather than an internal host or asset label. This is a public repository.

### Gate-aware acceptance criteria

An implementer will pass tests locally and then red the build, because two gates are
invisible from a clean local run:

- **A parameter-block change moves four derived-artifact pairs**, not two:
  `PfbDeadKeyReport`, `PfbApiDriftReport`, `PfbFieldCmdletMap`, `PfbPipelineSelectorMap`.
  Regenerate through `scripts/Assert-PfbDerivedArtifacts.ps1` (it has `-UpdateCommitted`),
  never a bare generator — a bare run records whatever the local spec cache happens to
  hold and the gate will report the same artifact stale again.
- **A new test file needs the two-line `BeforeAll`** from `Tests/PfbTestModule.ps1`, or
  the force-import ratio gate fails while the file passes locally.

Name whichever applies as an explicit criterion. Do not assume it is common knowledge.

## Template

```markdown
## Agent Brief

**Category:** bug / enhancement
**Summary:** one line
**Verification:** live-verified <date, what ran> / not verified — <why> / n/a — cannot reach the wire

**Current behavior:**
What happens now, and why it is wrong.

**Desired behavior:**
What should happen, including edge cases and error behaviour.

**Key interfaces:**
- Cmdlet, parameter, wire key or contract that changes, and what it becomes.

**Acceptance criteria:**
- [ ] Independently checkable statement
- [ ] ...
- [ ] Gate criteria, where they apply

**Out of scope:**
- What must not change, and why.
```

## Worked example

From issue #136, abridged. Note what it does *not* contain: no file paths, no line
numbers, no instruction about where to put the code.

```markdown
## Agent Brief

**Category:** bug
**Summary:** Three local-group write cmdlets have no parameter for the local directory
service identifier the array requires, so they cannot reach the array at all.
**Verification:** Live-verified against an AD-joined FlashBlade at REST 2.26, evidence in
the issue body, including a control that ruled out the account and the session.

**Current behavior:**
`New-PfbLocalGroup`, `Remove-PfbLocalGroup` and `Remove-PfbLocalGroupMember` send no
local directory service identifier. The array rejects all three with HTTP 400, and will
not infer the parent even when exactly one local directory service exists. There is no
argument a caller can pass to work around it, so the write side of the family is
unusable. `New-PfbLocalGroupMember` is the one that works — it already exposes an
optional `-LocalDirectoryService` sent as `local_directory_service_names`. The asymmetry
means a membership can be created that the module cannot then remove.

**Desired behavior:**
All four write cmdlets accept the identifier and send it. A caller who omits it gets the
array's own 400, unchanged — a deliberate non-change.

**Key interfaces:**
- Each of the three gains `-LocalDirectoryService`, matching the name, type, optionality
  and help wording of the one `New-PfbLocalGroupMember` already carries. Copy that shape;
  it is proven on the wire and consistency across the family is the point.
- Sent as `local_directory_service_names`.
- The value is a caller-supplied string passed through unaltered. Do not parse or validate it.

**Acceptance criteria:**
- [ ] All three accept the parameter and emit the key.
- [ ] Optional on all three. Omitting it leaves today's behaviour unchanged.
- [ ] Unit tests assert the key is present when supplied and absent when not, per cmdlet.
- [ ] Live-verified: create group, read, add member, remove member, delete group — the
      lifecycle the family currently cannot complete, with no raw-REST step in it.
- [ ] Derived-artifact gate passes; four pairs move, regenerated through the script.

**Out of scope:**
- Making the parameter mandatory. The array requires the key, so it is defensible, but it
  breaks existing callers of the one cmdlet that has it.
- Adding the `_ids` alternative selector.
- Inferring the directory service when only one exists — the array itself declines to.
- #127, an unrelated defect in one of the same cmdlets carrying an undecided tradeoff.
```

## What a bad brief looks like

```markdown
## Agent Brief
**Summary:** Fix the local group bug
**What to do:** The local group cmdlets are broken. Look at New-PfbLocalGroup.ps1
around line 28 and add the missing parameter.
```

No category, no verification, no acceptance criteria, no scope boundary, and two
references that go stale on the next refactor. An implementer reading this has to
rediscover everything the triage already established, and nothing tells it when to stop.
