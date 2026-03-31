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
    .PARAMETER TotalOnly
        Return only the total count.
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
        [string[]]$PolicyName,

        [Parameter(ParameterSetName = 'ByPolicyId')]
        [string[]]$PolicyId,

        [Parameter(ParameterSetName = 'ByName')]
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

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-access-policies/rules' -QueryParams $queryParams -AutoPaginate
    }
}
