function Update-PfbServer {
    <#
    .SYNOPSIS
        Updates an existing server on the FlashBlade.
    .DESCRIPTION
        Modifies server attributes such as DNS, directory services, and realm configurations.
    .PARAMETER Name
        The name of the server to update.
    .PARAMETER Id
        The ID of the server to update.
    .PARAMETER Attributes
        A hashtable of attributes to update on the server.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Update-PfbServer -Name "server1" -Attributes @{ dns = @{ domain = "example.com" } }

        Updates the DNS domain for server1.
    .EXAMPLE
        Update-PfbServer -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ dns = @{ domain = "newdomain.com" } }

        Updates the server identified by ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) {
            $body = $Attributes
        }
        else {
            $body = @{}
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update server')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'servers' -Body $body -QueryParams $queryParams
        }
    }
}
