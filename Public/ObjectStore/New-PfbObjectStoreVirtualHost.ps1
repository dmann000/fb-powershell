function New-PfbObjectStoreVirtualHost {
    <#
    .SYNOPSIS
        Creates a new object store virtual host on the FlashBlade.
    .DESCRIPTION
        Creates a new object store virtual host with the specified name and optional
        hostname. Use the Attributes parameter to supply a complete body hashtable,
        or use individual parameters to build the request.
    .PARAMETER Name
        The name of the object store virtual host to create.
    .PARAMETER Hostname
        The hostname to associate with the virtual host.
    .PARAMETER Attributes
        A hashtable of additional attributes for the virtual host body.
        When specified, this is used as the entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbObjectStoreVirtualHost -Name "s3.example.com"

        Creates a new object store virtual host named 's3.example.com'.
    .EXAMPLE
        New-PfbObjectStoreVirtualHost -Name "s3-vhost" -Hostname "s3.example.com"

        Creates a new object store virtual host with a specific hostname.
    .EXAMPLE
        New-PfbObjectStoreVirtualHost -Name "s3-vhost" -Attributes @{ hostname = "s3.example.com" }

        Creates a new object store virtual host using an attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [string]$Hostname,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($Hostname) { $body['hostname'] = $Hostname }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create object store virtual host')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-virtual-hosts' -Body $body -QueryParams $queryParams
    }
}
