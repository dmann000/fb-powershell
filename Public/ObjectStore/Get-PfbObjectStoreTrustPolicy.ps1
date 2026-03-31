function Get-PfbObjectStoreTrustPolicy {
    <#
    .SYNOPSIS
        Retrieves object store trust policies associated with roles.
    .DESCRIPTION
        Returns the trust policies attached to object store roles. A trust
        policy defines which principals (users, accounts, or services) are
        allowed to assume the role.
    .PARAMETER RoleName
        One or more role names whose trust policies to retrieve.
    .PARAMETER RoleId
        One or more role IDs whose trust policies to retrieve.
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
        Get-PfbObjectStoreTrustPolicy
        Returns all trust policies across all roles.
    .EXAMPLE
        Get-PfbObjectStoreTrustPolicy -RoleName "s3-admin-role"
        Returns the trust policy for the specified role.
    .EXAMPLE
        Get-PfbObjectStoreTrustPolicy -RoleId "10314f42-020d-7080-8013-000ddt400012" -Limit 10
        Returns the trust policy for a role identified by ID.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByRoleName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByRoleName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$RoleName,

        [Parameter(Mandatory, ParameterSetName = 'ByRoleId')]
        [string[]]$RoleId,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [switch]$TotalOnly,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allRoleNames = [System.Collections.Generic.List[string]]::new()
        $allRoleIds   = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($RoleName) { foreach ($n in $RoleName) { $allRoleNames.Add($n) } }
        if ($RoleId)   { foreach ($i in $RoleId)   { $allRoleIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allRoleNames.Count -gt 0) { $queryParams['role_names'] = $allRoleNames -join ',' }
        if ($allRoleIds.Count -gt 0)   { $queryParams['role_ids']   = $allRoleIds -join ',' }
        if ($Filter)                   { $queryParams['filter']     = $Filter }
        if ($Sort)                     { $queryParams['sort']       = $Sort }
        if ($Limit -gt 0)            { $queryParams['limit']      = $Limit }
        if ($TotalOnly)                { $queryParams['total_only'] = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-roles/object-store-trust-policies' -QueryParams $queryParams -AutoPaginate
    }
}
