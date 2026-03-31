function Get-PfbKeytabDownload {
    <#
    .SYNOPSIS
        Downloads a Kerberos keytab file from the FlashBlade.
    .DESCRIPTION
        The Get-PfbKeytabDownload cmdlet downloads a Kerberos keytab file from the connected
        Pure Storage FlashBlade. The keytab file is returned as binary data and can be saved
        to disk for use with Kerberos authentication services.
    .PARAMETER Name
        One or more keytab names to download. Accepts pipeline input.
    .PARAMETER Id
        One or more keytab IDs to download.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        The field and direction to sort results by (e.g., 'name' or 'name-').
    .PARAMETER Limit
        The maximum number of items to return per page.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbKeytabDownload -Name 'krb-keytab-1'

        Downloads the keytab file named 'krb-keytab-1'.
    .EXAMPLE
        Get-PfbKeytabDownload -Name 'krb-keytab-1' | Set-Content -Path 'C:\keytab.bin' -AsByteStream

        Downloads a keytab file and saves it to disk.
    .EXAMPLE
        Get-PfbKeytabDownload -Id '12345678-abcd-efgh-ijkl-123456789012'

        Downloads a keytab file by ID.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'keytabs/download' -QueryParams $queryParams -AutoPaginate
    }
}
