function Get-PfbObjectStoreUserAccessPolicy {
    <#
    .SYNOPSIS
        Retrieves the association between object store users and access policies.
    .DESCRIPTION
        Returns the cross-reference links between object store users and their
        associated access policies. Use this to discover which access policies
        are attached to a user or which users reference a given policy.
    .PARAMETER MemberName
        One or more user names to filter by (account/user format).
    .PARAMETER MemberId
        One or more user IDs to filter by.
    .PARAMETER PolicyName
        One or more access policy names to filter by.
    .PARAMETER PolicyId
        One or more access policy IDs to filter by.
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
        Get-PfbObjectStoreUserAccessPolicy
        Returns all user-to-access-policy associations.
    .EXAMPLE
        Get-PfbObjectStoreUserAccessPolicy -MemberName "acct1/user1"
        Returns access policies linked to the specified user.
    .EXAMPLE
        Get-PfbObjectStoreUserAccessPolicy -PolicyName "full-access-policy" -Limit 25
        Returns users linked to the specified access policy.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByMemberName', ValueFromPipelineByPropertyName)]
        [string[]]$MemberName,

        [Parameter(ParameterSetName = 'ByMemberId')]
        [string[]]$MemberId,

        [Parameter(ParameterSetName = 'ByPolicyName')]
        [string[]]$PolicyName,

        [Parameter(ParameterSetName = 'ByPolicyId')]
        [string[]]$PolicyId,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [switch]$TotalOnly,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allMemberNames = [System.Collections.Generic.List[string]]::new()
        $allMemberIds   = [System.Collections.Generic.List[string]]::new()
        $allPolicyNames = [System.Collections.Generic.List[string]]::new()
        $allPolicyIds   = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($MemberName) { foreach ($n in $MemberName) { $allMemberNames.Add($n) } }
        if ($MemberId)   { foreach ($i in $MemberId)   { $allMemberIds.Add($i) } }
        if ($PolicyName) { foreach ($n in $PolicyName) { $allPolicyNames.Add($n) } }
        if ($PolicyId)   { foreach ($i in $PolicyId)   { $allPolicyIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allMemberNames.Count -gt 0) { $queryParams['member_names'] = $allMemberNames -join ',' }
        if ($allMemberIds.Count -gt 0)   { $queryParams['member_ids']   = $allMemberIds -join ',' }
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }
        if ($allPolicyIds.Count -gt 0)   { $queryParams['policy_ids']   = $allPolicyIds -join ',' }
        if ($Filter)                     { $queryParams['filter']       = $Filter }
        if ($Sort)                       { $queryParams['sort']         = $Sort }
        if ($Limit -gt 0)              { $queryParams['limit']        = $Limit }
        if ($TotalOnly)                  { $queryParams['total_only']   = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-users/object-store-access-policies' -QueryParams $queryParams -AutoPaginate
    }
}
