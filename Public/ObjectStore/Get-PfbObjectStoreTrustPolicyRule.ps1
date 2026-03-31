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
    .PARAMETER PolicyId
        One or more trust policy IDs to filter by.
    .PARAMETER Name
        One or more fully-qualified rule names to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count.
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
        [string[]]$PolicyName,

        [Parameter(Mandatory, ParameterSetName = 'ByPolicyId')]
        [string[]]$PolicyId,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string[]]$Name,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [switch]$TotalOnly,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allPolicyNames = [System.Collections.Generic.List[string]]::new()
        $allPolicyIds   = [System.Collections.Generic.List[string]]::new()
        $allNames       = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($PolicyName) { foreach ($n in $PolicyName) { $allPolicyNames.Add($n) } }
        if ($PolicyId)   { foreach ($i in $PolicyId)   { $allPolicyIds.Add($i) } }
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
    }

    end {
        $queryParams = @{}
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }
        if ($allPolicyIds.Count -gt 0)   { $queryParams['policy_ids']   = $allPolicyIds -join ',' }
        if ($allNames.Count -gt 0)       { $queryParams['names']        = $allNames -join ',' }
        if ($Filter)                     { $queryParams['filter']       = $Filter }
        if ($Sort)                       { $queryParams['sort']         = $Sort }
        if ($Limit -gt 0)              { $queryParams['limit']        = $Limit }
        if ($TotalOnly)                  { $queryParams['total_only']   = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-roles/object-store-trust-policies/rules' -QueryParams $queryParams -AutoPaginate
    }
}
