function Write-PfbEmptyPipelineDiagnostic {
    <#
    .SYNOPSIS
        Explains an empty-pipeline suppression on the caller's verbose stream, and warns when the
        caller bound keys that were discarded.
    .DESCRIPTION
        Issue #126. Suppression is silent today, and broadening it broadens silence -- which is in
        tension with #121's finding that silence is the dangerous direction. But a warning on
        every suppressed pipeline would fire during ordinary no-match operation and train users to
        redirect the stream. So the rule splits by whether the caller supplied anything that was
        thrown away:

          - EVERY suppression emits Write-Verbose. Zero default noise, and -Verbose now explains
            why a piped call returned nothing.
          - A suppression where only NON-SELECTOR keys were bound additionally emits Write-Warning.
            The caller typed -Limit 10 and got nothing; they are owed the reason.

        THE WARNING IS DIAGNOSTICS, NOT THE SAFETY MECHANISM. The suppression is the safety
        action, and nothing about the guard's correctness depends on the message being seen. That
        is why a preference-controlled stream is adequate here, and why a non-terminating error --
        which would break any script running -ErrorAction Stop over a previously working pipeline
        -- is not warranted.

        THE WARNING HAS THE SAME EDGE, ONE PREFERENCE OVER. The paragraph above rejects an error
        for breaking -ErrorAction Stop scripts; a warning does exactly that to -WarningAction Stop
        scripts. Under -WarningAction Stop, or an inherited $WarningPreference = 'Stop', a
        discarding suppression now throws ActionPreferenceStopException where the same call
        returned rows before #126. Measured on both editions and pinned by
        Tests/Test-PfbEmptyPipelineRead.Tests.ps1.

        This is ACCEPTED as opt-in rather than overlooked, and the asymmetry with the error case is
        the reason. -ErrorAction Stop is set by scripts that want to stop on FAILURES, and a
        suppressed pipeline is not one, so an error would break callers who never asked for it.
        -WarningAction Stop is a caller stating that a warning alone is enough to stop them, and
        this is a warning -- so the throw is the behaviour they configured. The no-keys path is
        verbose-only and is unaffected by either preference.

        Writes through $Caller rather than Write-Verbose/Write-Warning so the record is attributed
        to the public cmdlet and honours ITS -Verbose and -WarningAction. Measured on both
        editions.

        Note what this does NOT restore. PR #125's "eleven cmdlets lost an actionable warning" is
        a correct count, but only four of the eleven catch a missing-selector error that fires on
        a bare empty-pipeline call; the other seven catch model or version capability errors that
        fire on direct calls too. Those four sit on the no-keys path, so they come back at VERBOSE
        level only. The loud-to-silent conversion is softened, not reversed.
    .PARAMETER Caller
        The public cmdlet's $PSCmdlet.
    .PARAMETER DiscardedKey
        The non-selector wire keys that were present in the query when the request was suppressed.
        Empty means the caller bound nothing -- verbose only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Caller,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$DiscardedKey
    )

    $cmdletName = $Caller.MyInvocation.MyCommand.Name
    $keys = @($DiscardedKey | Where-Object { $_ })

    if ($keys.Count -eq 0) {
        $Caller.WriteVerbose(
            "$cmdletName received an empty pipeline, so no object was selected. No request was issued.")
        return
    }

    # Ordinal, not Sort-Object: invariant LINGUISTIC order is not edition-stable between 5.1 and
    # 7, and this string is asserted on.
    $ordered = [string[]]$keys
    [System.Array]::Sort($ordered, [System.StringComparer]::Ordinal)

    $rendered = @($ordered | ForEach-Object {
            Resolve-PfbQueryKeyDisplayName -Caller $Caller -WireName $_
        })

    # "can only ... not select objects" is a modal, so ONE construction is grammatical for both a
    # single discarded key and several -- no branch on $rendered.Count.
    #
    # The remediation sentence must be true for all 130 guarded cmdlets. "Call <cmdlet> without
    # piping to read unfiltered" was not: Get-PfbFileSystemUserPerformance,
    # Get-PfbFileSystemGroupPerformance, Get-PfbObjectStoreTrustPolicyRule and Get-PfbS3ExportRule
    # carry a mandatory selector in EVERY parameter set, so a bare call prompts rather than reading
    # unfiltered. Advising on INTENT instead of promising an unfiltered read is universally true --
    # for those four, calling directly prompts for the selector they genuinely require -- and
    # avoids runtime parameter-set analysis for an advisory sentence covering 4 of 130.
    $message = "$cmdletName received an empty pipeline, so no object was selected. " +
    "$($rendered -join ', ') can only narrow or shape a result set, not select objects, " +
    "so no request was issued. If you did not intend to filter, call $cmdletName directly " +
    "instead of piping to it."

    $Caller.WriteVerbose($message)
    $Caller.WriteWarning($message)
}
