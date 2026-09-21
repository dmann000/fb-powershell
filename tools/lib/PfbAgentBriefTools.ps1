#Requires -Version 5.1
<#
.SYNOPSIS
    Classifies issue comments as agent briefs, and finds status:agent-ready issues without one.
.DESCRIPTION
    docs/TRIAGE-ROLES.md defines `status:agent-ready` as "a brief is attached", not "this
    issue looks small". Nothing enforced that. When the taxonomy was first applied, five
    issues carried the label and writing briefs against them demoted three of the five --
    the label was 60% wrong and no check in the repo could say so. A scheduled worker pops
    from that label, so an unbriefed issue there costs a wasted unattended run.

    The functions here are pure text classification over data the caller supplies. They do
    no network I/O on purpose: scripts/Assert-PfbAgentReadyBrief.ps1 owns fetching, so the
    decision logic is testable with no token, no rate limit and no lab
    (Tests/PfbAgentBriefTools.Tests.ps1 runs the real functions against fixtures rather
    than reading this file's source).

    WHAT IS DELIBERATELY NOT CHECKED. Whether the brief is any GOOD -- whether the
    acceptance criteria are actually checkable, whether the scope boundary is the right
    one -- is a judgement, and a gate that guessed at it would fail correct briefs and
    train people to pad sections. This answers only the structural question the label
    promises, which is the question that was silently wrong.

    The `#Requires -Version 5.1` above is not a compatibility commitment -- nothing here
    ships to the Gallery, and the 5.1/7 rules bind the module, not its tooling. It is
    simply true: this file needs nothing from 7, and the test suite's winps51 leg loads
    it. Claiming 7.0 instead would make the test file skip on that leg, which the coverage
    gate then requires to be declared as an exact skip count -- machinery bought for no
    benefit.
#>

# The eight sections docs/AGENT-BRIEF.md's template carries. Written as a literal rather
# than parsed out of the doc: the doc lives on a branch that may not have merged yet, and a
# gate that reads its own specification from a file can be silently disarmed by an edit to
# that file. If the template gains a section, both this list and the fixture in the test
# file have to be updated, which is the point.
$script:PfbAgentBriefRequiredSections = @(
    'Category'
    'Summary'
    'Verification'
    'Current behavior'
    'Desired behavior'
    'Key interfaces'
    'Acceptance criteria'
    'Out of scope'
)

# The exact label this gate is about. Compared with -contains, which is an exact
# case-insensitive string match rather than a substring test -- `status:agent-ready` must
# not be satisfied by a near neighbour such as a future `status:agent-ready-blocked`.
$script:PfbAgentReadyLabel = 'status:agent-ready'

function Test-PfbAgentBrief {
    <#
    .SYNOPSIS
        Decides whether one comment body is an agent brief, and what it is missing.
    .DESCRIPTION
        Returns IsBrief, MissingSections and VerificationForm.

        The `## Agent Brief` heading is the discriminator, not the words "agent brief".
        The demotion comments this gate exists alongside say things like "no agent brief
        can be written until the parameter question is settled" -- a keyword match would
        let the explanation for a missing brief satisfy the check for one.
    .PARAMETER CommentBody
        The raw markdown body of a single issue comment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$CommentBody
    )

    $missing = New-Object System.Collections.Generic.List[string]
    $result = [PSCustomObject]@{
        IsBrief          = $false
        MissingSections  = @()
        VerificationForm = 'absent'
    }

    if ([string]::IsNullOrWhiteSpace($CommentBody)) { return $result }

    # An ATX heading whose text is exactly "Agent Brief", at any level, any case. Anchored
    # to line start and end so a sentence containing the phrase cannot match.
    if ($CommentBody -notmatch '(?im)^[ \t]*#{1,6}[ \t]*Agent[ \t]+Brief[ \t]*$') { return $result }
    $result.IsBrief = $true

    foreach ($section in $script:PfbAgentBriefRequiredSections) {
        # The template writes each section as a bold label followed by a colon. Escape the
        # name: "n/a" is not in the list today but a future section with a regex
        # metacharacter in it would otherwise match the wrong thing, or nothing.
        $pattern = '(?im)^[ \t]*\*\*' + [regex]::Escape($section) + ':\*\*'
        if ($CommentBody -notmatch $pattern) { $missing.Add($section) }
    }
    $result.MissingSections = $missing.ToArray()

    $result.VerificationForm = Get-PfbAgentBriefVerificationForm -CommentBody $CommentBody
    return $result
}

function Get-PfbAgentBriefVerificationForm {
    <#
    .SYNOPSIS
        Which of docs/AGENT-BRIEF.md's three permitted verification claims a brief makes.
    .DESCRIPTION
        Returns 'live-verified', 'not-verified', 'not-applicable', 'unrecognised' or
        'absent'.

        This is parsed rather than merely counted present because it is the one section
        whose content is checkable without understanding the issue: "Verification: works
        correctly" passes a presence check while carrying no claim at all.

        Both an em dash and a double hyphen are accepted after the claim word. The doc
        uses an em dash; a keyboard produces two hyphens; they are the same claim, and a
        gate that rejected one would teach people to copy-paste punctuation instead of
        stating a verification. The dash is not required at all -- the claim word carries
        the meaning, and the reason after it is prose for a human.
    .PARAMETER CommentBody
        The raw markdown body of a single issue comment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$CommentBody
    )

    $match = [regex]::Match($CommentBody, '(?im)^[ \t]*\*\*Verification:\*\*[ \t]*(?<claim>[^\r\n]*)')
    if (-not $match.Success) { return 'absent' }

    $claim = $match.Groups['claim'].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($claim)) { return 'unrecognised' }

    if ($claim -match '^(?i)live[\s-]*verified') { return 'live-verified' }
    if ($claim -match '^(?i)not\s+verified') { return 'not-verified' }
    if ($claim -match '^(?i)n\s*/\s*a\b') { return 'not-applicable' }
    return 'unrecognised'
}

function Get-PfbAgentReadyViolation {
    <#
    .SYNOPSIS
        The status:agent-ready issues that do not carry a usable brief.
    .DESCRIPTION
        Takes normalised issue objects -- Number, Title, Labels (string[]), Comments
        (string[]) -- and returns one object per violation, carrying Number, Title, Reason,
        MissingSections and VerificationForm.

        Reason is 'no-brief' or 'incomplete-brief', and the distinction is the useful part
        of the output. They call for different actions: no brief at all means the issue was
        labelled optimistically and belongs back at status:triage, while an incomplete
        brief means someone started and the named sections are the remaining work.

        An unrecognised verification form is reported on the violation object but is NOT
        itself a violation. The three permitted forms are prose, so a legitimate fourth
        phrasing is likelier than a real defect, and failing a build over punctuation would
        make the gate the problem.

        Returns nothing when nothing violates, which PowerShell surfaces as $null. Wrap
        every call in @() -- an unwrapped empty result counts as 1 through Measure-Object.
    .PARAMETER Issue
        Normalised issue objects. An empty set passes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Issue
    )

    foreach ($candidate in @($Issue)) {
        if (@($candidate.Labels) -notcontains $script:PfbAgentReadyLabel) { continue }

        # Every comment that is structurally a brief, best first. An issue's brief gets
        # revised by posting a fuller comment rather than by editing the original, so
        # taking the first or the newest comment would both fail an issue that is fine.
        # "Best" is fewest missing sections; ordering is stable within a tie, so a single
        # brief behaves identically either way.
        $briefs = @()
        foreach ($body in @($candidate.Comments)) {
            $verdict = Test-PfbAgentBrief -CommentBody $body
            if ($verdict.IsBrief) { $briefs += $verdict }
        }

        if ($briefs.Count -eq 0) {
            [PSCustomObject]@{
                Number           = $candidate.Number
                Title            = $candidate.Title
                Reason           = 'no-brief'
                MissingSections  = @($script:PfbAgentBriefRequiredSections)
                VerificationForm = 'absent'
            }
            continue
        }

        $best = @($briefs | Sort-Object -Property { @($_.MissingSections).Count })[0]
        if (@($best.MissingSections).Count -gt 0) {
            [PSCustomObject]@{
                Number           = $candidate.Number
                Title            = $candidate.Title
                Reason           = 'incomplete-brief'
                MissingSections  = @($best.MissingSections)
                VerificationForm = $best.VerificationForm
            }
        }
    }
}
