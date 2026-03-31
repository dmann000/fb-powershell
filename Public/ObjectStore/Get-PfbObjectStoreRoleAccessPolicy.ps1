function Get-PfbObjectStoreRoleAccessPolicy {
    <#
    .SYNOPSIS
        Retrieves the association between object store roles and access policies.
    .DESCRIPTION
        Returns the cross-reference links between object store roles and their
        associated access policies. Use this to discover which access policies
        are attached to a role or which roles reference a given policy.
    .PARAMETER RoleName
        One or more role names to filter by.
    .PARAMETER RoleId
        One or more role IDs to filter by.
    .PARAMETER MemberName
        One or more access policy member names to filter by.
    .PARAMETER MemberId
        One or more access policy member IDs to filter by.
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
        Get-PfbObjectStoreRoleAccessPolicy
        Returns all role-to-access-policy associations.
    .EXAMPLE
        Get-PfbObjectStoreRoleAccessPolicy -RoleName "s3-admin-role"
        Returns access policies linked to the specified role.
    .EXAMPLE
        Get-PfbObjectStoreRoleAccessPolicy -MemberName "full-access-policy" -Limit 25
        Returns roles linked to the specified access policy.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByRoleName', ValueFromPipelineByPropertyName)]
        [string[]]$RoleName,

        [Parameter(ParameterSetName = 'ByRoleId')]
        [string[]]$RoleId,

        [Parameter(ParameterSetName = 'ByMemberName')]
        [string[]]$MemberName,

        [Parameter(ParameterSetName = 'ByMemberId')]
        [string[]]$MemberId,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [switch]$TotalOnly,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allRoleNames   = [System.Collections.Generic.List[string]]::new()
        $allRoleIds     = [System.Collections.Generic.List[string]]::new()
        $allMemberNames = [System.Collections.Generic.List[string]]::new()
        $allMemberIds   = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($RoleName)   { foreach ($n in $RoleName)   { $allRoleNames.Add($n) } }
        if ($RoleId)     { foreach ($i in $RoleId)     { $allRoleIds.Add($i) } }
        if ($MemberName) { foreach ($n in $MemberName) { $allMemberNames.Add($n) } }
        if ($MemberId)   { foreach ($i in $MemberId)   { $allMemberIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allRoleNames.Count -gt 0)   { $queryParams['role_names']   = $allRoleNames -join ',' }
        if ($allRoleIds.Count -gt 0)     { $queryParams['role_ids']     = $allRoleIds -join ',' }
        if ($allMemberNames.Count -gt 0) { $queryParams['member_names'] = $allMemberNames -join ',' }
        if ($allMemberIds.Count -gt 0)   { $queryParams['member_ids']   = $allMemberIds -join ',' }
        if ($Filter)                     { $queryParams['filter']       = $Filter }
        if ($Sort)                       { $queryParams['sort']         = $Sort }
        if ($Limit -gt 0)              { $queryParams['limit']        = $Limit }
        if ($TotalOnly)                  { $queryParams['total_only']   = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-roles/object-store-access-policies' -QueryParams $queryParams -AutoPaginate
    }
}
