function Remove-PfbServer {
    <#
    .SYNOPSIS
        Removes (destroys or eradicates) a server from the FlashBlade.
    .DESCRIPTION
        Destroys a server or eradicates a previously destroyed server (permanent delete).
        Server deletion uses DELETE with cascade_delete=directory-services to also remove
        the associated directory service configuration.
    .PARAMETER Name
        The name of the server to remove.
    .PARAMETER Id
        The ID of the server to remove.
    .PARAMETER Eradicate
        Permanently eradicate a destroyed server. Cannot be undone.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbServer -Name "server1"

        Destroys server1 and its associated directory services.
    .EXAMPLE
        Remove-PfbServer -Name "server1" -Eradicate

        Permanently eradicates a previously destroyed server.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [switch]$Eradicate,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if (-not $Eradicate) {
            # Destroy: DELETE with cascade to remove associated directory services
            if ($PSCmdlet.ShouldProcess($target, 'Destroy server')) {
                $queryParams['cascade_delete'] = 'directory-services'
                Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'servers' -QueryParams $queryParams
            }
        }
        else {
            # Eradicate: DELETE already-destroyed server
            if ($PSCmdlet.ShouldProcess($target, 'Eradicate server (PERMANENT)')) {
                $queryParams['cascade_delete'] = 'directory-services'
                Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'servers' -QueryParams $queryParams
            }
        }
    }
}
