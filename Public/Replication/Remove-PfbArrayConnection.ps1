function Remove-PfbArrayConnection {
    <#
    .SYNOPSIS
        Removes an array connection from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbArrayConnection cmdlet deletes a replication connection from the connected
        Everpure FlashBlade. This cmdlet has a high confirm impact and will prompt for
        confirmation by default. Removing an array connection will prevent any associated
        replication from continuing.

        An array connection has no name of its own -- the API resource carries only an id. Its
        human-readable identifier is the REMOTE array's name, so -RemoteName (aliased to -Name
        for compatibility) is how you select one by name.
    .PARAMETER RemoteName
        The name of the REMOTE array whose connection to remove. Aliased to -Name. Accepts
        pipeline input.
    .PARAMETER Id
        The ID of the array connection to remove. Accepts pipeline input by property name.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbArrayConnection -RemoteName "FB-B"

        Removes the connection to the remote array named "FB-B" after prompting for confirmation.
    .EXAMPLE
        Remove-PfbArrayConnection -RemoteName "FB-B" -Confirm:$false

        Removes the connection without prompting.
    .EXAMPLE
        Get-PfbArrayConnection | Where-Object status -eq 'disconnected' | Remove-PfbArrayConnection

        Removes all disconnected array connections, binding each one by its id through the
        pipeline.
    .EXAMPLE
        Get-PfbArrayConnection |
            Where-Object { $_.remote.id -eq '10314f42-020d-7080-8013-000133810cd0' } |
            Remove-PfbArrayConnection

        Selects a connection by the remote array's id. This cmdlet has no -RemoteId parameter,
        and on the write endpoints remote_ids only narrows an already-scoped request, so filter
        client-side and let the connection's own id bind through the pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByRemoteName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$RemoteName,

        [Parameter(ParameterSetName = 'ById', Mandatory, ValueFromPipelineByPropertyName)] [string]$Id,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($RemoteName) { $RemoteName } else { $Id }
        $queryParams = @{}
        if ($RemoteName) { $queryParams['remote_names'] = $RemoteName }
        if ($Id) { $queryParams['ids'] = $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Remove array connection')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'array-connections' -QueryParams $queryParams
        }
    }
}
