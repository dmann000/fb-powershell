function Get-PfbSupportDiagnosticsDetails {
    <#
    .SYNOPSIS
        Retrieves detailed support diagnostics information from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSupportDiagnosticsDetails cmdlet returns detailed information about support
        diagnostics jobs from the connected Pure Storage FlashBlade. This provides more granular
        information than Get-PfbSupportDiagnostics, including individual component status.
    .PARAMETER Name
        One or more diagnostics job names to retrieve details for. Accepts pipeline input.
    .PARAMETER Id
        One or more diagnostics job IDs to retrieve details for.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSupportDiagnosticsDetails

        Retrieves all support diagnostics details from the connected FlashBlade.
    .EXAMPLE
        Get-PfbSupportDiagnosticsDetails -Name "diag-20240101"

        Retrieves detailed diagnostics for the specified job.
    .EXAMPLE
        Get-PfbSupportDiagnosticsDetails -Filter "status='running'" -Limit 5

        Retrieves details for up to 5 running diagnostics jobs.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'support-diagnostics/details' -QueryParams $queryParams -AutoPaginate
    }
}
