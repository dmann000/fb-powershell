function Get-PfbNfsExportRule {
    <#
    .SYNOPSIS
        Retrieves NFS export policy rules from the FlashBlade.
    .DESCRIPTION
        Returns rules for NFS export policies. Rules define client access, permissions,
        and security settings for NFS exports. Filter by policy name to get rules for
        a specific policy.
    .PARAMETER PolicyName
        One or more NFS export policy names to retrieve rules for.
    .PARAMETER PolicyId
        One or more NFS export policy IDs to retrieve rules for.
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
        Get-PfbNfsExportRule

        Returns all NFS export policy rules.
    .EXAMPLE
        Get-PfbNfsExportRule -PolicyName "nfs-export-01"

        Returns rules for the policy named 'nfs-export-01'.
    .EXAMPLE
        Get-PfbNfsExportRule -PolicyName "nfs-export-01" -Name "nfs-export-01.1"

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

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'nfs-export-policies/rules' -QueryParams $queryParams -AutoPaginate
    }
}
