function Get-PfbSmbClientRule {
    <#
    .SYNOPSIS
        Retrieves SMB client policy rules from the FlashBlade.
    .DESCRIPTION
        Returns rules for SMB client policies. Rules define client access restrictions
        and settings for SMB connections. Filter by policy name to get rules for
        a specific policy.
    .PARAMETER PolicyName
        One or more SMB client policy names to retrieve rules for.
    .PARAMETER PolicyId
        One or more SMB client policy IDs to retrieve rules for.
    .PARAMETER Name
        One or more rule names to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'index' or 'index-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSmbClientRule

        Returns all SMB client policy rules.
    .EXAMPLE
        Get-PfbSmbClientRule -PolicyName "smb-client-01"

        Returns rules for the policy named 'smb-client-01'.
    .EXAMPLE
        Get-PfbSmbClientRule -PolicyName "smb-client-01" -Name "smb-client-01.1"

        Returns a specific rule by name within a policy.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByPolicyName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$PolicyName,

        [Parameter(ParameterSetName = 'ByPolicyId')]
        [string[]]$PolicyId,

        [Parameter()]
        [string[]]$Name,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allPolicyNames = [System.Collections.Generic.List[string]]::new()
        $allPolicyIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        Assert-PfbSelectorNotCoerced -Value $PolicyName -OriginalInput $PSItem -ParameterName 'PolicyName' -Hint (
            'Pipe the policy name instead, e.g. Get-PfbSmbClientPolicy | ' +
            'Select-Object -ExpandProperty name | Get-PfbSmbClientRule, or pass -PolicyName explicitly.')
        if ($PolicyName) { foreach ($n in $PolicyName) { $allPolicyNames.Add($n) } }
        if ($PolicyId)   { foreach ($i in $PolicyId)   { $allPolicyIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $Name
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }
        if ($allPolicyIds.Count -gt 0)   { $queryParams['policy_ids']   = $allPolicyIds -join ',' }

        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        $response = Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'smb-client-policies/rules' -QueryParams $queryParams -AutoPaginate

        # Lift the nested parent policy name to a top-level property so that piping a rule into a
        # cmdlet that binds -PolicyName by property name sends a scalar selector instead of a
        # stringified reference. Mutate in place: rebuilding the object would drop 'context' and
        # any wire field a future REST version adds.
        #
        # Do NOT delete this lift because the selector rail reports the pair Coerced -- that row is
        # an artifact. The rail's probe item is synthesized from the spec's declared response fields
        # and never runs a producer cmdlet, so a property added here at runtime cannot appear on it;
        # measured Bound against the real module once the lifted PolicyName is present. This makes
        # same-family piping work, but an item lifted by a different policy family can bind silently
        # when both policies share a name, where the guard used to throw. The rail cannot see that
        # cost because its spec-derived probes never carry runtime-added properties. Reasoning: issue #90.
        foreach ($item in @($response)) {
            if ($null -ne $item -and $null -ne $item.policy -and $null -ne $item.policy.name -and
                $item.PSObject.Properties.Name -notcontains 'PolicyName') {
                $item | Add-Member -MemberType NoteProperty -Name 'PolicyName' -Value $item.policy.name
            }
        }
        $response
    }
}
