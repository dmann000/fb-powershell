function Get-PfbObjectStoreAccessPolicyRole {
    <#
    .SYNOPSIS
        Retrieves the association between access policies and object store roles.
    .DESCRIPTION
        Returns the cross-reference links between object store access policies
        and object store roles. Use this to discover which roles are attached to
        a policy or which policies are attached to a role.
    .PARAMETER PolicyName
        One or more access policy names to filter by.
    .PARAMETER PolicyId
        One or more access policy IDs to filter by.
    .PARAMETER MemberName
        One or more role member names to filter by.
    .PARAMETER MemberId
        One or more role member IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'policy.name' or 'member.name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyRole
        Returns all access-policy-to-role associations.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyRole -PolicyName "full-access-policy"
        Returns roles linked to the specified access policy.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyRole -MemberName "s3-admin-role" -Limit 10
        Returns access policies linked to the specified role.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByPolicyName', ValueFromPipelineByPropertyName)]
        [string[]]$PolicyName,

        [Parameter(ParameterSetName = 'ByPolicyId')]
        [string[]]$PolicyId,

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
        $allPolicyNames = [System.Collections.Generic.List[string]]::new()
        $allPolicyIds   = [System.Collections.Generic.List[string]]::new()
        $allMemberNames = [System.Collections.Generic.List[string]]::new()
        $allMemberIds   = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($PolicyName) { foreach ($n in $PolicyName) { $allPolicyNames.Add($n) } }
        if ($PolicyId)   { foreach ($i in $PolicyId)   { $allPolicyIds.Add($i) } }
        if ($MemberName) { foreach ($n in $MemberName) { $allMemberNames.Add($n) } }
        if ($MemberId)   { foreach ($i in $MemberId)   { $allMemberIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }
        if ($allPolicyIds.Count -gt 0)   { $queryParams['policy_ids']   = $allPolicyIds -join ',' }
        if ($allMemberNames.Count -gt 0) { $queryParams['member_names'] = $allMemberNames -join ',' }
        if ($allMemberIds.Count -gt 0)   { $queryParams['member_ids']   = $allMemberIds -join ',' }
        if ($Filter)                     { $queryParams['filter']       = $Filter }
        if ($Sort)                       { $queryParams['sort']         = $Sort }
        if ($Limit -gt 0)              { $queryParams['limit']        = $Limit }
        if ($TotalOnly)                  { $queryParams['total_only']   = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-access-policies/object-store-roles' -QueryParams $queryParams -AutoPaginate
    }
}
