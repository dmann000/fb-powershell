function Get-PfbSupport {
    <#
    .SYNOPSIS
        Retrieves support configuration from a Pure Storage FlashBlade.
    .DESCRIPTION
        The Get-PfbSupport cmdlet returns the current support settings for the FlashBlade,
        including Phone Home status, proxy configuration, and remote assist state.
    .PARAMETER Name
        One or more support configuration names to retrieve.
    .PARAMETER Filter
        A server-side filter expression (e.g., "phonehome_enabled='true'").
    .PARAMETER Sort
        Sort field and optional direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSupport

        Returns the support configuration for the connected FlashBlade.
    .EXAMPLE
        Get-PfbSupport | Select-Object name, phonehome_enabled, remote_assist_active

        Retrieves support settings and displays key fields.
    .EXAMPLE
        Get-PfbSupport -Array $FlashBlade

        Returns the support configuration using a specific FlashBlade connection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [PSCustomObject]$Array
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
        if ($Filter)               { $queryParams['filter'] = $Filter }
        if ($Sort)                 { $queryParams['sort'] = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit'] = $Limit }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'support' -QueryParams $queryParams -AutoPaginate
    }
}
