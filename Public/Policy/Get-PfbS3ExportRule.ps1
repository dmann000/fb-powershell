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
        [Alias('policy_name')]
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
        Assert-PfbSelectorNotCoerced -Value $PolicyName -ParameterName 'PolicyName' -Hint (
            'Pipe the policy name instead, e.g. Get-PfbS3ExportPolicy | ' +
            'Select-Object -ExpandProperty name | Get-PfbS3ExportRule, or pass -PolicyName explicitly.')
        if ($PolicyName) { foreach ($n in $PolicyName) { $allPolicyNames.Add($n) } }
        if ($PolicyId)   { foreach ($i in $PolicyId)   { $allPolicyIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $Name
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }
        if ($allPolicyIds.Count -gt 0)   { $queryParams['policy_ids']   = $allPolicyIds -join ',' }

        $response = Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 's3-export-policies/rules' -QueryParams $queryParams -AutoPaginate

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
