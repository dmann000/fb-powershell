# Settled questions

Questions this project has closed, and the reasoning that closed them.

`docs/design/` holds questions we **answered**. This directory holds questions we
**settled against** — a claim found false, an approach rejected, a feature declined. The
reasoning outlives the closed issue, which is the point: a closing comment on a closed
issue is not somewhere anyone looks.

Read this directory before filing an issue, before planning work, and before concluding
that something obvious has been overlooked. Automated issue-filing must read it too:
deduplicating against *open* issues is not enough, because the finding we declined last
month is exactly the one a scanner will rediscover next month.

## What belongs here

One file per **concept**, not per issue. Several issues asking the same thing share a
file. Three shapes qualify:

- **A claim that turned out to be false.** The report was wrong, not unwanted.
- **An approach that was rejected** in favour of another, for work we are still doing.
- **A feature or change that was declined.**

## What does not belong here

**Anything closed because it was already implemented.** That is a built feature, not a
rejected request, and recording it here poisons the deduplication with a false negative —
the next scanner finding sees a match and stays silent about a real gap. Point at where
the feature lives in the closing comment instead.

**A deferral.** "Not now" is not settled. If you cannot write the `Premise` line below,
what you have is a deferral: leave the issue open with `status:blocked` and name the
blocker.

## Entry format

Each file is a short design note, not a database row. Prose, examples and code are
welcome. Five fields, in this order:

```markdown
# Concept name

One-paragraph statement of what is settled.

**Settled:** date, and by what — a measurement, a PR, a maintainer decision.
**Why:** the substantive reason. Not "we didn't want it".
**Premise:** the fact this rests on. The thing that could stop being true.
**What would reopen this:** the observable change that makes the entry stop binding.
**Prior requests:** issue links, one per line.
```

### Why `Premise` and `What would reopen this` exist

Because a recorded decision expires with its premise, and a rejection that outlives its
reasoning is worse than no record at all — it becomes the thing that blocks correct work,
with the authority of a written decision behind it.

Every entry here rests on something that was true when it was written. Say what that is,
and say what would falsify it. If a new issue matches an entry, the first question is not
"was this rejected?" but **"is the premise still true?"**

## Using it during triage

1. Read the directory. Match by concept, not keyword.
2. On a match, surface it rather than acting on it: *"this resembles `<entry>`; we settled
   it because X, and the premise was Y — does Y still hold?"*
3. Then one of three outcomes:
   - **Confirmed** — append the new issue to `Prior requests` and close it.
   - **Premise falsified** — delete or rewrite the entry and triage the issue normally.
     Deleting is correct; the entry was true when written and is not now.
   - **Distinct** — related but not the same. Triage normally, and consider whether the
     entry's wording invited the confusion.

Old issues are not reopened when an entry is retired. They are historical records; the
new issue carries the work.
