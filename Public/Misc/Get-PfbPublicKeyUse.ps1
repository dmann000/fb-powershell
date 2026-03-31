function Get-PfbPublicKeyUse {
    <#
    .SYNOPSIS
        Retrieves public key usage information from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbPublicKeyUse cmdlet returns information about how public keys are being
        used on the connected Pure Storage FlashBlade.
    .PARAMETER Name
        One or more public key names to filter by. Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbPublicKeyUse

        Retrieves all public key usage information.
    .EXAMPLE
        Get-PfbPublicKeyUse -Name "key-admin"

        Retrieves usage for the specified public key.
    .EXAMPLE
        Get-PfbPublicKeyUse -Limit 10

        Retrieves up to 10 public key usage entries.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'public-keys/uses' -QueryParams $queryParams -AutoPaginate
    }
}
