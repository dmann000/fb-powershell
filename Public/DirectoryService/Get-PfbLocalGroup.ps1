function Get-PfbLocalGroup {
    <#
    .SYNOPSIS
        Retrieves local groups from the FlashBlade.
    .DESCRIPTION
        Returns one or more local groups. Endpoint: GET /directory-services/local/groups.
    .PARAMETER Name
        One or more local group names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more local group IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbLocalGroup

        Retrieves all local groups.
    .EXAMPLE
        Get-PfbLocalGroup -Name "mydomain\share-admins"
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id)   { foreach ($i in $Id)   { $allIds.Add($i) } }
    }
    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames -Ids $allIds
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'directory-services/local/groups' -QueryParams $queryParams -AutoPaginate
    }
}
