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
        if ($PolicyName) { foreach ($n in $PolicyName) { $allPolicyNames.Add($n) } }
        if ($PolicyId)   { foreach ($i in $PolicyId)   { $allPolicyIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }
        if ($allPolicyIds.Count -gt 0)   { $queryParams['policy_ids']   = $allPolicyIds -join ',' }
        if ($Name)                        { $queryParams['names']        = $Name -join ',' }
        if ($Filter)                      { $queryParams['filter']       = $Filter }
        if ($Sort)                        { $queryParams['sort']         = $Sort }
        if ($Limit -gt 0)               { $queryParams['limit']        = $Limit }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'smb-client-policies/rules' -QueryParams $queryParams -AutoPaginate
    }
}
