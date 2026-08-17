function Get-PfbRealmDefaults {
    <#
    .SYNOPSIS
        Retrieves realm default settings from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbRealmDefaults cmdlet returns the default settings for realms on the
        connected FlashBlade.

        The selector on this endpoint is resource-specific: use -RealmName to select by realm
        name (wire key 'realm_names'). The endpoint does not accept the generic 'names' query key.
    .PARAMETER RealmName
        One or more realm names to retrieve defaults for. Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbRealmDefaults

        Retrieves all realm defaults from the connected FlashBlade.
    .EXAMPLE
        Get-PfbRealmDefaults -RealmName "realm-prod"

        Retrieves defaults for the specified realm.
    .EXAMPLE
        Get-PfbRealmDefaults -Sort "name" -Limit 10

        Retrieves up to 10 realm defaults sorted by name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$RealmName,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allRealmNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($RealmName) { foreach ($n in $RealmName) { $allRealmNames.Add($n) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        if ($allRealmNames.Count -gt 0) {
            $queryParams['realm_names'] = $allRealmNames -join ','
        }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'realms/defaults' -QueryParams $queryParams -AutoPaginate
    }
}
