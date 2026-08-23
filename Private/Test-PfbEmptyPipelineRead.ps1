function Test-PfbEmptyPipelineRead {
    <#
    .SYNOPSIS
        Detects an empty pipeline invocation that would issue a request the caller did not address.
    .DESCRIPTION
        Public collect-in-process cmdlets call this from end after building their final query
        hashtable. A piped invocation that produced no SELECTOR received no object to select;
        issuing the request would turn that absence into an unfiltered read or write.

        A SELECTOR is a query key whose bound the caller can enumerate or author -- identity
        (names, ids, *_names, *_ids) or a caller-authored predicate, which today means 'filter'
        alone. A key on $script:PfbNonSelectorQueryKeys narrows or shapes a result set the caller
        did not choose, so it does not rescue the request. Issue #126; design spec at
        docs/design/empty-pipeline-selector-policy-spec.md.

        Two properties of this function are load-bearing:

          - Direct calls are NEVER suppressed. ExpectingInput gates everything, so
            `Get-PfbX -Limit 10` remains the deliberate unfiltered read it has always been.
          - THE LIST DECIDES, NOT A SPELLING TEST. The shape test used by
            Tests/PfbSelectorPolicyCompleteness.Tests.ps1 is a CI construct and must never be
            consulted here, because the two have OPPOSITE DEFAULTS: an unmatched key is
            NOT-a-selector to the shape test and IS a selector to this list. Consulting it would
            reclassify 'filter' -- the module's one caller-authored predicate, which matches no
            identity shape -- as scope, and suppress a legitimately filtered call.

            The reason is NOT that the two disagree about context_names. They do not: it is
            absent from this list, so the list reads it as a SELECTOR, the same answer the shape
            test gives. It is moot in any case, because context_names is injected into a CLONE
            inside Invoke-PfbApiRequest after this function returns and is never in the hashtable
            inspected here. Earlier revisions of this comment asserted a disagreement; there is
            none, and the same false claim is worth not reintroducing.

        Its input is the PRE-REQUEST query state, not the fully built wire query: context_names is
        injected into a clone inside Invoke-PfbApiRequest after this returns, and
        continuation_token is written inside the pagination loop. Central injection needs its own
        tests, separate from this predicate's.

        Known and deliberate gap 1: a key with selector SPELLING can sit on a parameter addressing
        a CONTAINER rather than the returned objects, so
        `@() | Get-PfbBucketAccessPolicyRule -PolicyName 'x'` still returns every rule of that
        policy across all buckets. No per-key list can express that, because the harm is
        per-(key, cmdlet, which-parameter-is-piped). It is a missed guard rather than new harm.

        Known and deliberate gap 2: this classifies on key PRESENCE and never inspects the value.
        @{ names = $null } and @{ names = '' } are both "a selector is present", so both issue --
        and an empty selector reaching the wire is #121's exact harm. It is LATENT, not live, and
        the reason is a property of THE GUARDED SET rather than of Public/ as a whole: the 130
        guarded cmdlets are the only population this predicate can ever inspect, so an unguarded
        cmdlet's unconditional write is out of reach by construction. Across those 130 files, all
        73 selector writes sit behind a non-empty gate. Add-PfbCommonQueryParams gates names/ids on
        truthiness (Add-PfbCommonQueryParams.ps1:22-23), and the four writes that look
        unconditional to a grep are each inside a `.Count -gt 0` block --
        Get-PfbCertificateGroupCertificate.ps1:79-84 (two of them),
        Get-PfbNetworkInterfaceNeighbor.ps1:66-68 and Get-PfbRealmDefaults.ps1:62-64. Cmdlets that
        DO write a selector unconditionally exist -- Remove-PfbFleetMember.ps1:38-39 and
        New-PfbBucketAuditFilter.ps1:62-63 among sixteen such writes across eight cmdlets -- but
        none of them is guarded, so none can reach this predicate. Adding a value check would be a
        behaviour change beyond the #126 spec, so the current behaviour is pinned by test rather
        than altered here.

        Case sensitivity is part of the policy, not an oversight. $script:PfbNonSelectorQueryKeys
        uses StringComparer::Ordinal, so `LIMIT` does not match `limit`: it reads as unclassified,
        therefore as a selector, and the request issues. That is the safe direction -- a
        case-insensitive comparer would make the miss direction SUPPRESS a previously working call,
        while Ordinal's miss direction is to issue, which is that call's pre-#126 behaviour.
    .PARAMETER Caller
        The public cmdlet's $PSCmdlet.
    .PARAMETER QueryParams
        The final query hashtable the request is about to receive.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Caller,

        [AllowNull()]
        [System.Collections.IDictionary]$QueryParams
    )

    if (-not $Caller.MyInvocation.ExpectingInput) { return $false }

    $discarded = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $QueryParams) {
        foreach ($key in $QueryParams.Keys) {
            $name = [string]$key
            # First selector wins: the request is legitimate and nothing else needs examining.
            if (-not $script:PfbNonSelectorQueryKeys.Contains($name)) { return $false }
            $discarded.Add($name)
        }
    }

    Write-PfbEmptyPipelineDiagnostic -Caller $Caller -DiscardedKey $discarded.ToArray()
    return $true
}
