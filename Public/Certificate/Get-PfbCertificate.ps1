function Get-PfbCertificate {
    <#
    .SYNOPSIS
        Retrieves SSL/TLS certificate information from a Pure Storage FlashBlade.
    .DESCRIPTION
        The Get-PfbCertificate cmdlet returns certificate objects configured on the FlashBlade.
        Certificates can be retrieved by name, by ID, or all at once. Results support filtering,
        sorting, and pagination. The cmdlet accepts pipeline input for certificate names.
    .PARAMETER Name
        One or more certificate names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more certificate IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., 'status=''self-signed''').
    .PARAMETER Sort
        The field and direction to sort results by (e.g., 'name' or 'valid_to-').
    .PARAMETER Limit
        The maximum number of items to return per page.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbCertificate

        Returns all certificates configured on the connected FlashBlade.
    .EXAMPLE
        Get-PfbCertificate -Name 'management'

        Retrieves the certificate named 'management'.
    .EXAMPLE
        'management', 'replication' | Get-PfbCertificate

        Retrieves multiple certificates by piping their names to the cmdlet.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'certificates' -QueryParams $queryParams -AutoPaginate
    }
}
