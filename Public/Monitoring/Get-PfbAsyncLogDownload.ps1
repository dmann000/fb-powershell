function Get-PfbAsyncLogDownload {
    <#
    .SYNOPSIS
        Downloads the binary data of an asynchronous log collection from the FlashBlade.
    .DESCRIPTION
        The Get-PfbAsyncLogDownload cmdlet downloads the binary log data for a completed
        asynchronous log collection job from the connected Pure Storage FlashBlade. The
        result can be piped to Set-Content to save to disk.
    .PARAMETER Name
        The name of the async log job to download. Accepts pipeline input.
    .PARAMETER Id
        The ID of the async log job to download.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbAsyncLogDownload -Name "log-job-1"

        Downloads the log data for the async log job named "log-job-1".
    .EXAMPLE
        Get-PfbAsyncLogDownload -Name "log-job-1" | Set-Content -Path 'C:\logs\bundle.tar' -AsByteStream

        Downloads the log bundle and saves it to disk.
    .EXAMPLE
        Get-PfbAsyncLogDownload -Id "12345678-abcd-efgh-ijkl-123456789012"

        Downloads the log data by async log job ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string[]]$Id,

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
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']   = $allIds -join ',' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'logs-async/download' -QueryParams $queryParams -AutoPaginate
    }
}
