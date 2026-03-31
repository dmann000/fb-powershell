function Get-PfbS3ExportRule {
    <#
    .SYNOPSIS
        Retrieves S3 export policy rules from the FlashBlade.
    .DESCRIPTION
        Returns rules for S3 export policies. Rules define the specific export
        settings within an S3 export policy such as client access, permissions,
        and protocol configuration. Filter by policy name, policy ID, or rule name.
    .PARAMETER PolicyName
        One or more S3 export policy names to retrieve rules for.
    .PARAMETER PolicyId
        One or more S3 export policy IDs to retrieve rules for.
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
        Get-PfbS3ExportRule

        Returns all S3 export policy rules.
    .EXAMPLE
        Get-PfbS3ExportRule -PolicyName "s3-export-01"

        Returns rules for the policy named 's3-export-01'.
    .EXAMPLE
        Get-PfbS3ExportRule -PolicyName "s3-export-01" -Name "s3-export-01.1"

        Returns a specific rule by name within a policy.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPolicyName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByPolicyName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$PolicyName,

        [Parameter(Mandatory, ParameterSetName = 'ByPolicyId')]
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

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 's3-export-policies/rules' -QueryParams $queryParams -AutoPaginate
    }
}
