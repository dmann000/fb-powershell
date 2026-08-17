function Get-PfbLocalGroupMember {
    <#
    .SYNOPSIS
        Retrieves local group memberships from the FlashBlade.
    .DESCRIPTION
        Returns the members of local groups. Endpoint:
        GET /directory-services/local/groups/members.
    .PARAMETER GroupName
        One or more local group names whose members to list (sent as 'group_names').
        Aliased as 'Group' and 'group_name'. Named to match the top-level GroupName
        property this cmdlet lifts from each item's nested 'group' reference, so a
        piped membership binds the group's name rather than the group object. The
        rename is what resolved the shadowing: measured on the real module, the
        parameter NAME beats the alias in by-property-name binding, so an item
        carrying both a lifted string 'GroupName' and the object-valued 'group'
        binds 'GroupName'. The 'Group' alias can still match that object on a
        producer with no lifted property, which is what the process block guards.
    .PARAMETER Member
        One or more member names to filter by (sent as 'member_names').
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbLocalGroupMember -GroupName "mydomain\share-admins"

        Lists the members of the local group.
    .EXAMPLE
        Get-PfbLocalGroupMember -Group "mydomain\share-admins"

        The same call using the 'Group' alias, which is retained for compatibility.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Group', 'group_name')]
        [string[]]$GroupName,
        [Parameter()] [string[]]$Member,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allGroups = [System.Collections.Generic.List[string]]::new()
    }
    process {
        # -GroupName keeps [Alias('Group', 'group_name')]: the parameter name beats the alias
        # in by-property-name lookup, and the alias is load-bearing for
        # GET /directory-services/roles, whose `group` is string-valued. This guard covers the
        # object-valued `group` on the members item, which coerces whole into the selector.
        #
        # Do NOT "fix" this pair by dropping ValueFromPipeline. Binding has FOUR passes, not three,
        # and pass 4 is ByPropertyName WITH coercion, so a ByPropertyName-only parameter whose ALIAS
        # matches the object-valued `group` still binds it stringified: the coercion moves from
        # pass 3 to pass 4 and the pair stays red. Dropping the `Group` alias instead is a breaking
        # change for -Group callers and costs the /directory-services/roles bind. Reasoning: #90.
        Assert-PfbSelectorNotCoerced -Value $GroupName -ParameterName 'GroupName' -Hint (
            'Pipe the group name instead, e.g. Get-PfbLocalGroup | Select-Object -ExpandProperty name | ' +
            'Get-PfbLocalGroupMember, or pass -GroupName explicitly.')
        if ($GroupName) { foreach ($g in $GroupName) { $allGroups.Add($g) } }
    }
    end {
        $queryParams = @{}
        if ($allGroups.Count -gt 0) { $queryParams['group_names']  = $allGroups -join ',' }
        if ($Member)                { $queryParams['member_names'] = $Member -join ',' }
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        $response = Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'directory-services/local/groups/members' -QueryParams $queryParams -AutoPaginate

        # Lift the nested parent group name to a top-level property so that piping a membership into
        # a cmdlet that binds -GroupName by property name sends a scalar selector instead of a
        # stringified reference. Mutate in place: rebuilding the object would drop 'context' and
        # any wire field a future REST version adds.
        foreach ($item in @($response)) {
            if ($null -ne $item -and $null -ne $item.group -and $null -ne $item.group.name -and
                $item.PSObject.Properties.Name -notcontains 'GroupName') {
                $item | Add-Member -MemberType NoteProperty -Name 'GroupName' -Value $item.group.name
            }
        }
        $response
    }
}
