function Get-PfbKeytab {
    <#
    .SYNOPSIS
        Retrieves FlashBlade Kerberos keytab entries.
    .DESCRIPTION
        Returns Kerberos keytab entries configured on the FlashBlade. Keytabs are used
        for Kerberos-based authentication with Active Directory or other KDC services.
    .PARAMETER Name
        One or more keytab names to retrieve.
    .PARAMETER Id
        One or more keytab IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbKeytab

        Retrieves all keytab entries on the FlashBlade.
    .EXAMPLE
        Get-PfbKeytab -Name "krb-keytab-1"

        Retrieves the keytab entry named 'krb-keytab-1'.
    .EXAMPLE
        Get-PfbKeytab -Limit 10 -Sort "name"

        Retrieves up to 10 keytab entries sorted by name.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'keytabs' -QueryParams $queryParams -AutoPaginate
    }
}
