# Bare pipeline chaining into `Update-*` cannot resolve a parameter set

Reported as a defect affecting 37 cmdlets: that piping an object straight into an
`Update-Pfb*` cmdlet leaves PowerShell unable to choose between the `Individual` and
`Attributes` parameter sets introduced by the write-cmdlet body-parameter work, so the
call fails with an ambiguity error.

**This was false when it was filed**, not merely stale by the time it was read.

**Settled:** 2026-08-12, closed `not planned`. Confirmed by reading the parameter
declarations, not by inference from the convention.

**Why:** `-Attributes` is `Mandatory` in both `*Attributes` parameter sets, and has been
since the body-parameter work landed on 2026-07-31. A mandatory parameter present in one
set and absent from the other is exactly what disambiguates them — PowerShell resolves
the set on the presence of `-Attributes`, and a piped object that does not supply it
binds to the `Individual` set without ambiguity. The condition the report describes
cannot arise.

**Premise:** `-Attributes` remains `Mandatory` in every `*Attributes` parameter set. That
is what does the disambiguating; nothing else does.

**What would reopen this:** `-Attributes` becoming optional in any of those sets, or a
third parameter set being added that a piped object could also satisfy. Either change
makes the reported ambiguity real. A cmdlet added later that copies the shape *without*
the mandatory marker is the most likely route.

**How the wrong conclusion was reached**, since the mechanism matters more than the
verdict: the report generalised from the convention's shape rather than reading the
declarations, and no control was run against a cmdlet that should have been unaffected.
A finding derived from a pattern is a hypothesis about the code, not a measurement of it.
Filing it publicly cost a retraction.

**Prior requests:**

- #89 — "Bare pipeline chaining into `Update-*` cannot resolve a parameter set (37 cmdlets)"
