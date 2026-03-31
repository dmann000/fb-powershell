function Update-PfbSyslogServer {
    <#
    .SYNOPSIS
        Updates an existing syslog server configuration on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbSyslogServer cmdlet modifies attributes of an existing syslog server
        configuration on the connected Pure Storage FlashBlade. The target server can be
        identified by name or ID. Supports pipeline input and ShouldProcess for confirmation.
    .PARAMETER Name
        The name of the syslog server to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the syslog server to update.
    .PARAMETER Attributes
        A hashtable of syslog server attributes to modify (e.g., URI, transport protocol).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSyslogServer -Name "syslog-prod" -Attributes @{ uri = "tcp://newsyslog.example.com:514" }

        Updates the URI of the syslog server named "syslog-prod".
    .EXAMPLE
        Update-PfbSyslogServer -Id "10314f42-020d-7080-8013-000ddt400090" -Attributes @{ enabled = $true }

        Enables the syslog server identified by the specified ID.
    .EXAMPLE
        Get-PfbSyslogServer -Name "syslog-prod" | Update-PfbSyslogServer -Attributes @{ uri = "tls://syslog.corp.com:6514" }

        Pipes a syslog server object and updates its URI to use TLS transport.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }
        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update syslog server')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'syslog-servers' -Body $Attributes -QueryParams $queryParams
        }
    }
}
