function New-PfbServer {
    <#
    .SYNOPSIS
        Creates a new server on the FlashBlade.
    .DESCRIPTION
        Creates a server with the specified configuration. The API automatically creates
        a directory service named "{servername}_nfs" for the new server. A request body
        is required by the API even if no additional attributes are specified.
    .PARAMETER Name
        The name of the server to create.
    .PARAMETER Attributes
        A hashtable of additional attributes to set on the server.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbServer -Name "server1"

        Creates a new server named server1 with default settings.
    .EXAMPLE
        New-PfbServer -Name "server1" -Attributes @{ dns = @{ domain = "example.com" } }

        Creates a new server with a DNS domain configuration.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) {
        $body = $Attributes
    }
    else {
        $body = @{}
    }

    # API requires create_ds query param with value "{servername}_nfs"
    $queryParams = @{
        'names'     = $Name
        'create_ds' = "${Name}_nfs"
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Create server')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'servers' -Body $body -QueryParams $queryParams
    }
}
