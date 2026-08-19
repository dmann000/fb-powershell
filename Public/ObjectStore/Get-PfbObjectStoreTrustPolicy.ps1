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
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allRoleNames = [System.Collections.Generic.List[string]]::new()
        $allRoleIds   = [System.Collections.Generic.List[string]]::new()
    }

    process {
        Assert-PfbSelectorNotCoerced -Value $RoleName -OriginalInput $PSItem -ParameterName 'RoleName' -Hint (
            'Pipe the role name instead, e.g. Get-PfbObjectStoreRole | ' +
            'Select-Object -ExpandProperty name | Get-PfbObjectStoreTrustPolicy, or pass -RoleName explicitly.')
        if ($RoleName) { foreach ($n in $RoleName) { $allRoleNames.Add($n) } }
        if ($RoleId)   { foreach ($i in $RoleId)   { $allRoleIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        if ($allRoleNames.Count -gt 0) { $queryParams['role_names'] = $allRoleNames -join ',' }
        if ($allRoleIds.Count -gt 0)   { $queryParams['role_ids']   = $allRoleIds -join ',' }

        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        $response = Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-roles/object-store-trust-policies' -QueryParams $queryParams -AutoPaginate

        # Lift the nested parent role name to a top-level property so that piping a trust policy
        # into a cmdlet that binds -RoleName by property name sends a scalar selector instead of a
        # stringified reference. Mutate in place: rebuilding the object would drop 'context' and
        # any wire field a future REST version adds.
        #
        # Do NOT delete this lift because the selector rail reports the pair Coerced -- that row is
        # an artifact. The rail's probe item is synthesized from the spec's declared response fields
        # and never runs a producer cmdlet, so a property added here at runtime cannot appear on it;
        # measured Bound against the real module once the lifted RoleName is present. A Coerced row
        # from a DIFFERENT producer endpoint is real, not artifact: the lift only reaches items this
        # cmdlet returns, which is what the process-block guard covers. Reasoning: issue #90.
        foreach ($item in @($response)) {
            if ($null -ne $item -and $null -ne $item.role -and $null -ne $item.role.name -and
                $item.PSObject.Properties.Name -notcontains 'RoleName') {
                $item | Add-Member -MemberType NoteProperty -Name 'RoleName' -Value $item.role.name
            }
        }
        $response
    }
}
