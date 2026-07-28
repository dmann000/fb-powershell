function Update-PfbSyslogServer {
    <#
    .SYNOPSIS
        Updates an existing syslog server configuration on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbSyslogServer cmdlet modifies attributes of an existing syslog server
        configuration on the connected Everpure FlashBlade. The target server can be
        identified by name or ID. Supports pipeline input and ShouldProcess for confirmation.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the syslog server to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the syslog server to update.
    .PARAMETER Services
        Valid values are `data-audit` and `management`.
    .PARAMETER Sources
        The network interfaces used for communication with the syslog server.
    .PARAMETER Uri
        The URI of the syslog server in the format PROTOCOL://HOSTNAME:PORT.
    .PARAMETER Attributes
        A hashtable of syslog server attributes to modify (e.g., URI, transport protocol).
        Mutually exclusive with the individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSyslogServer -Name "syslog-prod" -Uri "tcp://newsyslog.example.com:514"

        Updates the URI of the syslog server named "syslog-prod" using a typed parameter.
    .EXAMPLE
        Update-PfbSyslogServer -Id "10314f42-020d-7080-8013-000ddt400090" -Attributes @{ enabled = $true }

        Enables the syslog server identified by the specified ID.
    .EXAMPLE
        Get-PfbSyslogServer -Name "syslog-prod" | Update-PfbSyslogServer -Attributes @{ uri = "tls://syslog.corp.com:6514" }

        Pipes a syslog server object and updates its URI to use TLS transport.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [ValidateSet('data-audit', 'management')]
        [string[]]$Services,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$Sources,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Uri,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Every value-carrying parameter is guarded by ContainsKey, never by truthiness --
            # see the canonical explanation in Update-PfbAdmin.ps1.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Services')) { $body['services'] = @($Services) }
            if ($PSBoundParameters.ContainsKey('Uri'))      { $body['uri']      = $Uri }

            # Constraint 8(b): sources is an ARRAY OF REFERENCES (item schema is
            # {id, name, resource_type}), so the parameter is [string[]] and the projection is
            # assigned INLINE -- constraint 7 forbids an intermediate local.
            if ($PSBoundParameters.ContainsKey('Sources')) {
                $body['sources'] = @($Sources | ForEach-Object { @{ name = $_ } })
            }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update syslog server')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'syslog-servers' -Body $body -QueryParams $queryParams
        }
    }
}
