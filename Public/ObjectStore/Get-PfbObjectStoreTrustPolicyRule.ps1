function Get-PfbObjectStoreTrustPolicyRule {
    <#
    .SYNOPSIS
        Retrieves trust policy rules for object store roles.
    .DESCRIPTION
        Returns the individual rules within trust policies attached to object
        store roles. Each rule defines conditions under which a principal can
        assume the role.
    .PARAMETER PolicyName
        One or more trust policy names to filter by.
    .PARAMETER Name
        One or more fully-qualified rule names to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbObjectStoreTrustPolicyRule
        Returns all trust policy rules.
    .EXAMPLE
        Get-PfbObjectStoreTrustPolicyRule -PolicyName "s3-admin-role/trust-policy"
        Returns rules for the specified trust policy.
    .EXAMPLE
        Get-PfbObjectStoreTrustPolicyRule -Name "s3-admin-role/trust-policy/rule1" -Limit 10
        Returns the specified trust policy rule.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPolicyName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByPolicyName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('policy_name')]
        [string[]]$PolicyName,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string[]]$Name,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allPolicyNames = [System.Collections.Generic.List[string]]::new()
        $allNames       = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($PolicyName) { foreach ($n in $PolicyName) { $allPolicyNames.Add($n) } }
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }

        $response = Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-roles/object-store-trust-policies/rules' -QueryParams $queryParams -AutoPaginate

        # Lift the nested parent policy name to a top-level property so that piping a rule into a
        # cmdlet that binds -PolicyName by property name sends a scalar selector instead of a
        # stringified reference. Mutate in place: rebuilding the object would drop 'context' and
        # any wire field a future REST version adds.
        foreach ($item in @($response)) {
            if ($null -ne $item -and $null -ne $item.policy -and $null -ne $item.policy.name -and
                $item.PSObject.Properties.Name -notcontains 'PolicyName') {
                $item | Add-Member -MemberType NoteProperty -Name 'PolicyName' -Value $item.policy.name
            }
        }
        $response
    }
}
