function Get-PfbLogTargetFileSystem {
    <#
    .SYNOPSIS
        Retrieves log-target file-system configurations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbLogTargetFileSystem cmdlet returns one or more log-target file-system
        configurations from the connected Pure Storage FlashBlade. Results can be filtered
        by name, ID, or a server-side filter expression.
    .PARAMETER Name
        One or more log-target file-system names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more log-target file-system IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbLogTargetFileSystem

        Retrieves all log-target file-system configurations.
    .EXAMPLE
        Get-PfbLogTargetFileSystem -Name "log-fs-target1"

        Retrieves the log-target file-system configuration named "log-fs-target1".
    .EXAMPLE
        Get-PfbLogTargetFileSystem -Filter "enabled='true'" -Sort "name" -Limit 10

        Retrieves up to 10 enabled log-target file systems sorted by name.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
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
        if ($allNames.Count -gt 0) { $queryParams['names']  = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']    = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter'] = $Filter }
        if ($Sort)                 { $queryParams['sort']   = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']  = $Limit }

        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'log-targets/file-systems' -QueryParams $queryParams -AutoPaginate
        }
        catch {
            if ($_ -match 'not supported' -or $_ -match 'Operation not permitted') {
                Write-Warning "Log target file systems are not supported on this FlashBlade model or configuration."
                return
            }
            throw
        }
    }
}
