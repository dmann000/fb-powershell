function Get-PfbPublicKey {
    <#
    .SYNOPSIS
        Retrieves public keys from the FlashBlade.
    .DESCRIPTION
        The Get-PfbPublicKey cmdlet returns public key objects from the connected Pure Storage
        FlashBlade. Public keys are used for SSH authentication and API client configurations.
        Results support filtering, sorting, and pagination.
    .PARAMETER Name
        One or more public key names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more public key IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        The field and direction to sort results by (e.g., 'name' or 'name-').
    .PARAMETER Limit
        The maximum number of items to return per page.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbPublicKey

        Returns all public keys configured on the connected FlashBlade.
    .EXAMPLE
        Get-PfbPublicKey -Name 'admin-ssh-key'

        Retrieves the public key named 'admin-ssh-key'.
    .EXAMPLE
        Get-PfbPublicKey -Filter "key_type='ssh-rsa'" -Limit 10

        Retrieves up to 10 RSA public keys.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'public-keys' -QueryParams $queryParams -AutoPaginate
    }
}
