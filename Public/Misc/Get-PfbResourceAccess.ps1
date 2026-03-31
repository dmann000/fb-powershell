function Get-PfbResourceAccess {
    <#
    .SYNOPSIS
        Retrieves resource access entries from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbResourceAccess cmdlet returns resource access control entries from the
        connected Pure Storage FlashBlade. Resource accesses define which users or groups
        have access to specific resources.
    .PARAMETER Name
        One or more resource access names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more resource access IDs to retrieve.
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
        Get-PfbResourceAccess -Name "access-prod"

        Retrieves the resource access entry with the specified name.
    .EXAMPLE
        Get-PfbResourceAccess -Filter "resource_type='file-system'" -Limit 20

        Retrieves up to 20 file system resource access entries.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($allIds.Count -gt 0) { $queryParams['ids'] = $allIds -join ',' }
        if ($Filter) { $queryParams['filter'] = $Filter }
        if ($Sort) { $queryParams['sort'] = $Sort }
        if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'resource-accesses' -QueryParams $queryParams -AutoPaginate
    }
}
