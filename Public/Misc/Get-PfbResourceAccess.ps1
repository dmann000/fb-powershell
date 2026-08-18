function Get-PfbResourceAccess {
    <#
    .SYNOPSIS
        Retrieves resource access entries from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbResourceAccess cmdlet returns resource access control entries from the
        connected Pure Storage FlashBlade. Resource accesses define which users or groups
        have access to specific resources.
    .PARAMETER Id
        One or more resource access IDs to retrieve. Binds from the pipeline by
        property name, so resource access objects (which carry 'id') can be piped
        in directly.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbResourceAccess

        Retrieves all resource access entries from the connected FlashBlade.
    .EXAMPLE
        Get-PfbResourceAccess -Id "10314f42-020d-7080-8013-000ddt400012"

        Retrieves the resource access entry with the specified ID.
    .EXAMPLE
        Get-PfbResourceAccess -Filter "resource_type='file-system'" -Limit 20

        Retrieves up to 20 file system resource access entries.
    .EXAMPLE
        Get-PfbResourceAccess | Where-Object { $_.scope.name -eq 'admin' } | Remove-PfbResourceAccess

        Removes the matching resource access entries; -Id binds from the 'id'
        property of each piped object.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName)] [string[]]$Id,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Ids $allIds
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'resource-accesses' -QueryParams $queryParams -AutoPaginate
    }
}
