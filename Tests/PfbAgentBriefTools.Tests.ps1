#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    The classifier behind the status:agent-ready brief gate.
.DESCRIPTION
    These tests run the real logic against in-memory fixtures rather than asserting on the
    script's source, which is the opposite choice from Tests/AssertDerivedArtifacts.ps1 and
    for a specific reason: that gate's logic needs tools/specs/ and minutes of regeneration,
    so it can only be read. This one is pure text classification over issue comments, so it
    executes in milliseconds with no network, no token and no lab.

    WHAT THE GATE IS FOR. `status:agent-ready` is defined in docs/TRIAGE-ROLES.md as "a brief
    is attached", not "this issue looks small". When the taxonomy was first applied, five
    issues carried the label and writing briefs against them demoted three -- the label was
    60% wrong, and nothing in the repo could tell. A scheduled worker pops from that label,
    so an unbriefed issue there costs a wasted unattended run. This is the assertion that
    stops the label silently overpromising again.

    WHY MISSING AND INCOMPLETE ARE DIFFERENT VERDICTS. They call for different human
    actions: no brief at all means the issue was labelled optimistically and should move
    back to status:triage; an incomplete brief means someone started and the specific
    missing sections are the work. Collapsing them into one "invalid" result would throw
    away the only part of the message worth reading.

    WHY THE VERIFICATION LINE IS PARSED AND NOT JUST COUNTED PRESENT. It is the one section
    whose content is checkable without understanding the issue: docs/AGENT-BRIEF.md permits
    exactly three forms, and "Verification: works correctly" satisfies a presence check
    while carrying no claim. An unrecognised form is reported, not thrown on, because the
    three forms are prose and a legitimate fourth phrasing is likelier than a real defect.

    5.1 CONSTRAINT: this file runs on the winps51 leg. No ternaries, no `??`, no pipeline
    chain operators, no `ConvertFrom-Json -Depth`.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:libPath = Join-Path $script:repoRoot 'tools/lib/PfbAgentBriefTools.ps1'
    . $script:libPath

    # U+2014 built from its code point rather than typed, so this file stays pure ASCII.
    # Not cosmetic: PSUseBOMForUnicodeEncodedFile is one of five rules CI holds at a
    # repo-wide zero, and it fires on any non-ASCII file without a byte-order mark. A
    # literal em dash here would red the analyzer job, and adding a BOM to satisfy it
    # would make this the only BOM-bearing file in the tree. The character itself is
    # load-bearing test data -- docs/AGENT-BRIEF.md writes its verification forms with an
    # em dash -- so it cannot simply be replaced with a hyphen.
    $script:emDash = [string][char]0x2014

    # A brief that satisfies every requirement in docs/AGENT-BRIEF.md. Built once and
    # mutated by the incomplete-brief cases below, so a new required section added to the
    # implementation without being added here fails loudly instead of passing vacuously.
    $script:validBrief = @'
## Agent Brief

**Category:** bug
**Summary:** Three local-group write cmdlets omit the directory-service identifier the array requires.
**Verification:** live-verified 2026-09-21, reproduced against an AD-joined FlashBlade at REST 2.26

**Current behavior:**
The request omits the required key and the array rejects it.

**Desired behavior:**
The identifier is sent as a query key on all three cmdlets.

**Key interfaces:**
- `-LocalDirectoryService` becomes the `local_directory_service_names` query key.

**Acceptance criteria:**
- [ ] All three cmdlets send the key.
- [ ] The four derived-artifact pairs are regenerated through the gate script.

**Out of scope:**
- The read cmdlets, which already send it.
'@
}

Describe 'Test-PfbAgentBrief' {

    Context 'deciding whether a comment is a brief at all' {

        It 'recognises a complete brief' {
            $result = Test-PfbAgentBrief -CommentBody $script:validBrief
            $result.IsBrief | Should -BeTrue
            @($result.MissingSections).Count | Should -Be 0
        }

        It 'does not treat an ordinary comment as a brief' {
            $result = Test-PfbAgentBrief -CommentBody 'Reproduced this on my array too, same 400.'
            $result.IsBrief | Should -BeFalse
        }

        It 'does not treat a comment that merely mentions the phrase as a brief' {
            # The heading is the discriminator, not the words. Otherwise the demotion
            # comments -- which say "no agent brief was written because..." -- would
            # themselves satisfy the gate they exist to explain.
            $body = 'Moving back to triage: an agent brief cannot be written until the parameter question is settled.'
            $result = Test-PfbAgentBrief -CommentBody $body
            $result.IsBrief | Should -BeFalse
        }

        It 'accepts the heading regardless of case' {
            $body = $script:validBrief -replace '## Agent Brief', '## AGENT BRIEF'
            $result = Test-PfbAgentBrief -CommentBody $body
            $result.IsBrief | Should -BeTrue
        }

        It 'returns IsBrief false for an empty or whitespace body' {
            (Test-PfbAgentBrief -CommentBody '').IsBrief | Should -BeFalse
            (Test-PfbAgentBrief -CommentBody "   `n  ").IsBrief | Should -BeFalse
        }
    }

    Context 'reporting which required sections are absent' {

        It 'names a single missing section' {
            $body = $script:validBrief -replace '(?s)\*\*Out of scope:\*\*.*$', ''
            $result = Test-PfbAgentBrief -CommentBody $body
            $result.IsBrief | Should -BeTrue
            $result.MissingSections | Should -Contain 'Out of scope'
            @($result.MissingSections).Count | Should -Be 1
        }

        It 'names every missing section, not just the first' {
            $body = "## Agent Brief`n`n**Category:** bug`n**Summary:** something"
            $result = Test-PfbAgentBrief -CommentBody $body
            $result.MissingSections | Should -Contain 'Verification'
            $result.MissingSections | Should -Contain 'Current behavior'
            $result.MissingSections | Should -Contain 'Out of scope'
        }

        It 'requires the repo-specific Verification section' {
            # docs/AGENT-BRIEF.md calls this one of "two sections this repo requires".
            # A generic brief template has no reason to carry it, which is exactly why
            # its absence has to be an error rather than a warning.
            $body = $script:validBrief -replace '\*\*Verification:\*\*[^\r\n]*', ''
            $result = Test-PfbAgentBrief -CommentBody $body
            $result.MissingSections | Should -Contain 'Verification'
        }
    }

    Context 'classifying the Verification line' {

        It 'recognises a live-verified claim' {
            $result = Test-PfbAgentBrief -CommentBody $script:validBrief
            $result.VerificationForm | Should -Be 'live-verified'
        }

        It 'recognises an explicit not-verified claim with an em dash' {
            $body = $script:validBrief -replace '\*\*Verification:\*\*[^\r\n]*',
                ('**Verification:** not verified ' + $script:emDash + ' no AD-joined array is reachable this week')
            (Test-PfbAgentBrief -CommentBody $body).VerificationForm | Should -Be 'not-verified'
        }

        It 'recognises the same claim written with a double hyphen' {
            # The doc uses an em dash; a keyboard produces two hyphens. Both are the same
            # claim, and a gate that rejected one of them would be teaching people to
            # copy-paste punctuation rather than to state a verification.
            $body = $script:validBrief -replace '\*\*Verification:\*\*[^\r\n]*',
                '**Verification:** not verified -- no AD-joined array is reachable this week'
            (Test-PfbAgentBrief -CommentBody $body).VerificationForm | Should -Be 'not-verified'
        }

        It 'recognises the cannot-reach-the-wire form' {
            $body = $script:validBrief -replace '\*\*Verification:\*\*[^\r\n]*',
                ('**Verification:** n/a ' + $script:emDash + ' cannot reach the wire')
            (Test-PfbAgentBrief -CommentBody $body).VerificationForm | Should -Be 'not-applicable'
        }

        It 'reports an unrecognised form rather than accepting it' {
            $body = $script:validBrief -replace '\*\*Verification:\*\*[^\r\n]*',
                '**Verification:** works correctly'
            $result = Test-PfbAgentBrief -CommentBody $body
            $result.VerificationForm | Should -Be 'unrecognised'
            # Still a brief, and still structurally complete -- the section is present.
            $result.IsBrief | Should -BeTrue
            $result.MissingSections | Should -Not -Contain 'Verification'
        }

        It 'reports no form when the section is absent' {
            $body = $script:validBrief -replace '\*\*Verification:\*\*[^\r\n]*', ''
            (Test-PfbAgentBrief -CommentBody $body).VerificationForm | Should -Be 'absent'
        }
    }
}

Describe 'Get-PfbAgentReadyViolation' {

    BeforeAll {
        function New-TestIssue {
            param(
                [int]$Number,
                [string[]]$Labels,
                [string[]]$Comments = @()
            )
            return [PSCustomObject]@{
                Number   = $Number
                Title    = "issue $Number"
                Labels   = @($Labels)
                Comments = @($Comments)
            }
        }
    }

    It 'passes an agent-ready issue carrying a complete brief' {
        $issues = @(New-TestIssue -Number 136 -Labels 'status:agent-ready' -Comments $script:validBrief)
        @(Get-PfbAgentReadyViolation -Issue $issues).Count | Should -Be 0
    }

    It 'flags an agent-ready issue with no comments at all' {
        $issues = @(New-TestIssue -Number 138 -Labels 'status:agent-ready')
        $violations = @(Get-PfbAgentReadyViolation -Issue $issues)
        @($violations).Count | Should -Be 1
        $violations[0].Number | Should -Be 138
        $violations[0].Reason | Should -Be 'no-brief'
    }

    It 'flags an agent-ready issue whose comments are all ordinary discussion' {
        $issues = @(New-TestIssue -Number 139 -Labels 'status:agent-ready' -Comments @(
            'Seeing this too.', 'Bumping -- still reproduces on 2.26.'))
        $violations = @(Get-PfbAgentReadyViolation -Issue $issues)
        @($violations).Count | Should -Be 1
        $violations[0].Reason | Should -Be 'no-brief'
    }

    It 'flags an incomplete brief separately from a missing one, and names the sections' {
        $partial = "## Agent Brief`n`n**Category:** bug`n**Summary:** something"
        $issues = @(New-TestIssue -Number 142 -Labels 'status:agent-ready' -Comments $partial)
        $violations = @(Get-PfbAgentReadyViolation -Issue $issues)
        @($violations).Count | Should -Be 1
        $violations[0].Reason | Should -Be 'incomplete-brief'
        $violations[0].MissingSections | Should -Contain 'Out of scope'
    }

    It 'finds the brief when it is not the only comment' {
        $issues = @(New-TestIssue -Number 132 -Labels 'status:agent-ready' -Comments @(
            'Filed from the drift report.', $script:validBrief, 'Thanks, picking this up.'))
        @(Get-PfbAgentReadyViolation -Issue $issues).Count | Should -Be 0
    }

    It 'prefers the most complete brief when an issue carries more than one' {
        # A brief gets revised by posting a second, fuller comment rather than editing the
        # first. Taking the newest or the first would both fail an issue that is fine.
        $partial = "## Agent Brief`n`n**Category:** bug`n**Summary:** first pass"
        $issues = @(New-TestIssue -Number 133 -Labels 'status:agent-ready' -Comments @(
            $partial, $script:validBrief))
        @(Get-PfbAgentReadyViolation -Issue $issues).Count | Should -Be 0

        $reversed = @(New-TestIssue -Number 134 -Labels 'status:agent-ready' -Comments @(
            $script:validBrief, $partial))
        @(Get-PfbAgentReadyViolation -Issue $reversed).Count | Should -Be 0
    }

    It 'ignores an issue that does not carry the label' {
        # The gate is about one label's promise. Every other issue in the backlog is
        # allowed to have no brief -- that is the normal state.
        $issues = @(
            New-TestIssue -Number 152 -Labels @('status:triage', 'priority:P1')
            New-TestIssue -Number 84 -Labels @('status:needs-design')
        )
        @(Get-PfbAgentReadyViolation -Issue $issues).Count | Should -Be 0
    }

    It 'matches the label exactly rather than by prefix' {
        # `status:agent-ready` must not be satisfied by a near neighbour, and must not
        # match a hypothetical `status:agent-ready-blocked`. Substring matching here is
        # the same class of defect as the "powershell" substring guard in this project.
        $issues = @(New-TestIssue -Number 200 -Labels @('status:agent-ready-later'))
        @(Get-PfbAgentReadyViolation -Issue $issues).Count | Should -Be 0
    }

    It 'reports every violating issue, not just the first' {
        $issues = @(
            New-TestIssue -Number 138 -Labels 'status:agent-ready'
            New-TestIssue -Number 136 -Labels 'status:agent-ready' -Comments $script:validBrief
            New-TestIssue -Number 139 -Labels 'status:agent-ready' -Comments @('nope')
        )
        $violations = @(Get-PfbAgentReadyViolation -Issue $issues)
        @($violations).Count | Should -Be 2
        @($violations | ForEach-Object { $_.Number }) | Should -Not -Contain 136
    }

    It 'treats an empty issue set as passing' {
        # Wrapped in @() on purpose. A function that returns nothing yields $null, which
        # counts as 0 through @() and as 1 through Measure-Object -- the coercing-wrapper
        # trap this repo has already paid for. The caller must use the same wrapping.
        @(Get-PfbAgentReadyViolation -Issue @()).Count | Should -Be 0
    }

    It 'carries the unrecognised verification form through as advisory, not as a violation' {
        $body = $script:validBrief -replace '\*\*Verification:\*\*[^\r\n]*', '**Verification:** works correctly'
        $issues = @(New-TestIssue -Number 201 -Labels 'status:agent-ready' -Comments $body)
        @(Get-PfbAgentReadyViolation -Issue $issues).Count | Should -Be 0
    }
}
