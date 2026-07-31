function Get-PfbRealmStorageClass {
    <#
    .SYNOPSIS
        Retrieves realm storage class space information from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbRealmStorageClass cmdlet returns space usage broken down by storage class
        per realm on the connected Pure Storage FlashBlade.
    .PARAMETER Name
        One or more realm names to retrieve storage class data for. Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbRealmStorageClass

        Retrieves storage class space for all realms.
    .EXAMPLE
        Get-PfbRealmStorageClass -Name "realm-prod"

        Retrieves storage class space for the specified realm.
    .EXAMPLE
        Get-PfbRealmStorageClass -Sort "name" -Limit 10

        Retrieves up to 10 realm storage class entries sorted by name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'realms/space/storage-classes' -QueryParams $queryParams -AutoPaginate
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
