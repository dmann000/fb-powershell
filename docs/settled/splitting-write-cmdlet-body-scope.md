# Splitting the write-cmdlet body-parameter work by cmdlet family

The remaining write-cmdlet body-parameter scope (#65) is delivered as **one coherent
correctness pass**, not split into per-cmdlet or per-family pull requests against the
individual coverage issues.

**Settled:** 2026-07-23, decided with the maintainer and reaffirmed when the follow-up
scope was separated out.

**Why:** the split does not partition the work. Of roughly 48 affected cmdlets, only
about three map cleanly onto an existing family issue; the rest have no owning issue at
all, so a family-first split would orphan the large majority and leave them tracked
nowhere. The fixes also share one convention — how a typed body parameter coexists with
the catch-all attributes hashtable — and reviewing that convention once, against every
cmdlet it touches, is what makes it reviewable. Several of the affected cmdlets are
compliance-relevant, and the maintainer asked specifically that those be reviewed
together rather than arriving piecemeal across unrelated PRs.

**Premise:** the great majority of the remaining cmdlets still have no owning family
issue, and the fixes still share a single convention.

**What would reopen this:** the coverage issues growing to cover the orphaned cmdlets, so
that a family split would actually partition the work — or the remaining scope shrinking
far enough that "one pass" and "one family" become the same thing. Re-derive what remains
before assuming either; several children of the original scope have already shipped, and
the issue text is older than the tree.

**Not covered by this entry:** splitting for any *other* reason. A genuinely independent
defect that happens to live in one of these cmdlets is its own issue and its own PR. This
entry is about not fragmenting the shared convention, not about never touching these
files separately.

**Prior requests:**

- #65 — "Follow-up scope for #31 (write-cmdlet body parameters): everything deliberately deferred"
