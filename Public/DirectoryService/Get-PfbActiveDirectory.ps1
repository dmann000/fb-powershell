function Get-PfbActiveDirectory {
    <#
    .SYNOPSIS
        Retrieves FlashBlade Active Directory configuration.
    .DESCRIPTION
        The Get-PfbActiveDirectory cmdlet returns Active Directory configurations from the
        connected Pure Storage FlashBlade. This includes domain membership details, computer
        account information, and join status. Supports pipeline input and server-side filtering.
    .PARAMETER Name
        One or more Active Directory configuration names to retrieve. Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbActiveDirectory

        Retrieves all Active Directory configurations from the connected FlashBlade.
    .EXAMPLE
        Get-PfbActiveDirectory -Name "ad1"

        Retrieves the Active Directory configuration named "ad1".
    .EXAMPLE
        Get-PfbActiveDirectory -Filter "domain='corp.example.com'"

        Retrieves Active Directory configurations for the specified domain.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [string]$Filter,
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'active-directory' -QueryParams $queryParams -AutoPaginate
    }
}
