# Authoring GitHub Actions workflows in this repo

Concrete, non-obvious authoring rules -- all discovered the hard way on this
repo's CI (see the `fb-powershell-ci-infrastructure` / `github-actions-syntax-gotchas`
memories for the incident history).

## `${{ }}` expressions require single-quoted string literals

`format(" text", x)` or `""` inside a `${{ }}` expression is a parse error
("Unexpected symbol: '\"'"), even though the *surrounding* YAML scalar can be
single- or double-quoted however you like.

If the outer YAML value needs to contain the expression's single-quoted
literals without escaping, make the **outer** YAML scalar double-quoted
(`title: "...${{ format('...', x) }}..."`) rather than single-quoted (which
would force doubling every inner `'` per YAML's own escape rule).

## `shell:` cannot read the `matrix` context in a workflow -- but can in a composite action

`shell: ${{ matrix.shell }}` at step level in a **workflow** fails with
"Unrecognized named-value: 'matrix'" -- only a reduced context set is
available to `shell:`/`working-directory:` at job or step level, even though
`matrix` works fine in `runs-on:`, `name:`, `env:`, `run:`, `if:`, etc.

If different matrix entries need different shells, split into separate jobs
(one non-matrixed job per shell) instead of trying to matrix the shell
itself.

**Exception:** `shell:` *does* accept `${{ inputs.* }}` inside a **composite
action** (`.github/actions/*/action.yml`) -- this is how one composite action
can serve both PowerShell editions across a matrix. Still not `matrix`
directly, only `inputs.*`.

## Action version pins are not uniform across actions

Don't assume every action's latest major version lines up -- check each one
individually. Examples seen in this repo: `actions/checkout@v7` exists, but
`actions/cache` has no v7 (v6 is its latest major); `create-pull-request` v6
and v7 are both Node 20, so v8 was required to actually clear the Node 20
deprecation warning, not merely optional.

## A `pull_request` run tests the MERGE commit, not your branch tip

Two consequences that look like flaky CI and are not:

- A green run **goes stale when `main` moves**, with nothing in the branch
  changing. If the merge would now fail -- a ceiling that no longer holds, a
  test `main` just added -- the next run reds on a commit nobody touched.
- **A manual re-run cannot re-measure a moved base.** Re-running replays the
  recorded `GITHUB_SHA` against that run's workflow definition, so
  `actions/checkout@v7` with no `ref:` override checks out the same old merge
  commit. The re-run looks fresh while testing the same stale tree.

To genuinely re-measure against a moved `main`: `gh pr update-branch` (adds a
merge commit, harmless if the PR is squash-merged), or close and reopen the PR
(`reopened` is in the default `pull_request` types, at the cost of a close
event for watchers).

## Getting GitHub's actual parse error instead of guessing

A workflow file with a syntax/schema problem produces no useful detail in
the Actions UI or `gh run view` for a `push`-triggered run -- "no jobs were
run" / "this run likely failed because of a workflow file issue" is all
you get.

**Reliable diagnostic:** `gh workflow run <file> --repo <owner>/<repo> --ref <branch>`
-- if the file has a validation problem, the command itself fails with the
exact parser message and line/column. This requires the workflow to declare
`workflow_dispatch: {}` as one of its triggers; add it (temporarily, or
permanently -- it's generally useful) if missing, specifically to unlock this
diagnostic path.
