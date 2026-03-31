function Get-PfbFileSystemStorageClass {
    <#
    .SYNOPSIS
        Retrieves file system storage class space information from the FlashBlade.
    .DESCRIPTION
        Returns space consumption broken down by storage class for file systems.
        Supports filtering by name, ID, or advanced filter expressions.
        Auto-paginates by default.
    .PARAMETER Name
        One or more file system names to retrieve storage class data for. Accepts pipeline input.
    .PARAMETER Id
        One or more file system IDs to retrieve storage class data for.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbFileSystemStorageClass
        Returns storage class space information for all file systems.
    .EXAMPLE
        Get-PfbFileSystemStorageClass -Name "fs01"
        Returns storage class space information for file system 'fs01'.
    .EXAMPLE
        Get-PfbFileSystemStorageClass -Filter "name='fs01'" -Sort "name" -Limit 50
        Returns filtered and sorted storage class data.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$Limit,

        [Parameter()]
        [switch]$TotalOnly,

        [Parameter()]
        [PSCustomObject]$Array
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
        if ($allNames.Count -gt 0) { $queryParams['names']      = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']        = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter']     = $Filter }
        if ($Sort)                 { $queryParams['sort']       = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']      = $Limit }
        if ($TotalOnly)            { $queryParams['total_only'] = 'true' }

        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-systems/space/storage-classes' -QueryParams $queryParams -AutoPaginate
        }
        catch {
            if ($_ -match 'not supported' -or $_ -match 'Storage classes') {
                Write-Warning "Storage classes are not supported on this FlashBlade model. This feature requires FlashBlade//S or FlashBlade//E."
                return
            }
            throw
        }
    }
}
