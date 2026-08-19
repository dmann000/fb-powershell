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
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }
        if ($allPolicyIds.Count -gt 0)   { $queryParams['policy_ids']   = $allPolicyIds -join ',' }
        if ($allMemberNames.Count -gt 0) { $queryParams['member_names'] = $allMemberNames -join ',' }
        if ($allMemberIds.Count -gt 0)   { $queryParams['member_ids']   = $allMemberIds -join ',' }

        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        $response = Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-access-policies/object-store-roles' -QueryParams $queryParams -AutoPaginate

        # Lift the nested parent names to top-level properties so that piping an association into a
        # cmdlet that binds -PolicyName or -MemberName by property name sends a scalar selector
        # instead of a stringified reference. Add only when the nested object AND its name are
        # non-null: a top-level property holding $null still binds downstream and would send an
        # empty selector, which makes the consumer return everything. Mutate in place: rebuilding
        # the object would drop 'context' and any wire field a future REST version adds.
        foreach ($item in @($response)) {
            if ($null -ne $item -and $null -ne $item.policy -and $null -ne $item.policy.name -and
                $item.PSObject.Properties.Name -notcontains 'PolicyName') {
                $item | Add-Member -MemberType NoteProperty -Name 'PolicyName' -Value $item.policy.name
            }
            if ($null -ne $item -and $null -ne $item.member -and $null -ne $item.member.name -and
                $item.PSObject.Properties.Name -notcontains 'MemberName') {
                $item | Add-Member -MemberType NoteProperty -Name 'MemberName' -Value $item.member.name
            }
        }
        $response
    }
}
