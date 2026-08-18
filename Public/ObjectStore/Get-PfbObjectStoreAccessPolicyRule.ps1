function Get-PfbObjectStoreAccessPolicyRule {
    <#
    .SYNOPSIS
        Retrieves object store access policy rules from the FlashBlade.
    .DESCRIPTION
        Returns the individual rules within object store access policies.
        Each rule specifies an effect (allow/deny), actions, resources, and
        optional conditions. Rules can be filtered by policy or by rule name.
    .PARAMETER PolicyName
        One or more access policy names whose rules to retrieve.
    .PARAMETER PolicyId
        One or more access policy IDs whose rules to retrieve.
    .PARAMETER Name
        One or more fully-qualified rule names to retrieve (policy/rule format).
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyRule
        Returns all access policy rules.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyRule -PolicyName "full-access-policy"
        Returns all rules belonging to the specified policy.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyRule -Name "full-access-policy/rule1" -Sort "name" -Limit 50
        Returns the specified rule with sorting and limit options.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByPolicyName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('policy_name')]
        [string[]]$PolicyName,

        [Parameter(ParameterSetName = 'ByPolicyId')]
        [string[]]$PolicyId,

        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$Name,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allPolicyNames = [System.Collections.Generic.List[string]]::new()
        $allPolicyIds   = [System.Collections.Generic.List[string]]::new()
        $allNames       = [System.Collections.Generic.List[string]]::new()
    }

    process {
        Assert-PfbSelectorNotCoerced -Value $PolicyName -OriginalInput $PSItem -ParameterName 'PolicyName' `
            -BindingPropertyName 'policy_name' -Hint (
            'Pipe the policy name instead, e.g. Get-PfbObjectStoreAccessPolicy | ' +
            'Select-Object -ExpandProperty name | Get-PfbObjectStoreAccessPolicyRule, ' +
            'or pass -PolicyName explicitly.')
        if ($PolicyName) { foreach ($n in $PolicyName) { $allPolicyNames.Add($n) } }
        if ($PolicyId)   { foreach ($i in $PolicyId)   { $allPolicyIds.Add($i) } }
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }
        if ($allPolicyIds.Count -gt 0)   { $queryParams['policy_ids']   = $allPolicyIds -join ',' }

        $response = Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-access-policies/rules' -QueryParams $queryParams -AutoPaginate

        # Lift the nested parent policy name to a top-level property so that piping a rule into a
        # cmdlet that binds -PolicyName by property name sends a scalar selector instead of a
        # stringified reference. Mutate in place: rebuilding the object would drop 'context' and
        # any wire field a future REST version adds.
        #
        # Do NOT delete this lift because the selector rail reports the pair Coerced -- that row is
        # an artifact. The rail's probe item is synthesized from the spec's declared response fields
        # and never runs a producer cmdlet, so a property added here at runtime cannot appear on it;
        # measured Bound against the real module once the lifted PolicyName is present. A Coerced
        # row from a DIFFERENT producer endpoint is real, not artifact: the lift only reaches items
        # this cmdlet returns, which is what the process-block guard covers. Reasoning: issue #90.
        foreach ($item in @($response)) {
            if ($null -ne $item -and $null -ne $item.policy -and $null -ne $item.policy.name -and
                $item.PSObject.Properties.Name -notcontains 'PolicyName') {
                $item | Add-Member -MemberType NoteProperty -Name 'PolicyName' -Value $item.policy.name
            }
        }
        $response
    }
}
