# Typed object model

The module does not stamp its output with custom type names, does not expose
type-constrained `-InputObject` parameter sets, and ships no `format.ps1xml`. Output is
plain `PSCustomObject` shaped by the API response, and pipeline chaining works by
**property-name binding** alone.

This was one half of a two-part pipeline plan. The other half — `ValueFromPipelineByPropertyName`
with identity aliases, and per-item `begin`/`process`/`end` handling — shipped, and covers
several hundred parameters. Parent-to-child chaining such as
`Get-PfbObjectStoreAccessPolicyRole | New-PfbObjectStoreAccessPolicyRole` works today
because of it.

**Settled:** 2026-07-08, evaluated and rejected during the pipeline work. Confirmed
absent by inspection: no type-stamping helper, no `OutputType` naming a custom type
anywhere in `Public/`, no formats file in the manifest.

**Why:** after property-name binding landed, exactly **one** cmdlet family still had a
pipeline ambiguity, and no cheap fix exists for it. `New-PfbFileSystemSnapshot` carries
an alias that lets a piped object's `name` property bind to its source parameter. That is
correct for a file system, whose `name` is the file system's own name, and wrong for a
snapshot, whose `name` is a compound identifier. Removing the alias closes the bad path
and breaks the good one, which is also the only real one — users snapshot a file system,
not a snapshot. Only a type-based guard can tell the two apart, and building the whole
typed-object model to disambiguate one family is disproportionate.

**Premise:** exactly one cmdlet family is affected, and its bad path is not a workflow
anyone performs. The cost/benefit rests entirely on that count being one.

**What would reopen this:** a second, and especially a third, family showing the same
ambiguity — at which point the model stops being disproportionate. Also: a concrete
demand for formatted table output or type-based parameter validation, neither of which
has been asked for. Note the reverse does *not* reopen it: the existing family's alias is
a known, accepted, low-risk limitation, and re-reporting it in isolation is not new
information.

**Prior requests:**

- Raised and closed within the original pipeline implementation plan; no standalone issue
  was filed.
