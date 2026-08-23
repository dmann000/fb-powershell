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

    $message = "$cmdletName received an empty pipeline, so no object was selected. " +
    "$($rendered -join ', ') narrow or shape a result set but do not select objects, " +
    "so no request was issued. Call $cmdletName without piping to read unfiltered."

    $Caller.WriteVerbose($message)
    $Caller.WriteWarning($message)
}
