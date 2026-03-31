function Get-PfbSupportDiagnostics {
    <#
    .SYNOPSIS
        Retrieves support diagnostics jobs from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSupportDiagnostics cmdlet returns support diagnostics job information from
        the connected Pure Storage FlashBlade. Diagnostics jobs collect system information
        for troubleshooting and support purposes.
    .PARAMETER Name
        One or more diagnostics job names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more diagnostics job IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSupportDiagnostics

        Retrieves all support diagnostics jobs from the connected FlashBlade.
    .EXAMPLE
        Get-PfbSupportDiagnostics -Name "diag-20240101"

        Retrieves the support diagnostics job with the specified name.
    .EXAMPLE
        Get-PfbSupportDiagnostics -Filter "status='completed'" -Limit 10

        Retrieves up to 10 completed diagnostics jobs.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'support-diagnostics' -QueryParams $queryParams -AutoPaginate
    }
}
