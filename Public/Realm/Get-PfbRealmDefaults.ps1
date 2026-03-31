function Get-PfbRealmDefaults {
    <#
    .SYNOPSIS
        Retrieves realm default settings from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbRealmDefaults cmdlet returns the default settings for realms on the
        connected Pure Storage FlashBlade.
    .PARAMETER Name
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
        Get-PfbRealmDefaults -Name "realm-prod"

        Retrieves defaults for the specified realm.
    .EXAMPLE
        Get-PfbRealmDefaults -Sort "name" -Limit 10

        Retrieves up to 10 realm defaults sorted by name.
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
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($Filter) { $queryParams['filter'] = $Filter }
        if ($Sort) { $queryParams['sort'] = $Sort }
        if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'realms/defaults' -QueryParams $queryParams -AutoPaginate
    }
}
