function Get-PfbLocalGroupMember {
    <#
    .SYNOPSIS
        Retrieves local group memberships from the FlashBlade.
    .DESCRIPTION
        Returns the members of local groups. Endpoint:
        GET /directory-services/local/groups/members.
    .PARAMETER Group
        One or more local group names whose members to list (sent as 'group_names').
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
        Get-PfbLocalGroupMember -Group "mydomain\share-admins"

        Lists the members of the local group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Group,
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
        if ($Group) { foreach ($g in $Group) { $allGroups.Add($g) } }
    }
    end {
        $queryParams = @{}
        if ($allGroups.Count -gt 0) { $queryParams['group_names']  = $allGroups -join ',' }
        if ($Member)                { $queryParams['member_names'] = $Member -join ',' }
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'directory-services/local/groups/members' -QueryParams $queryParams -AutoPaginate
    }
}
