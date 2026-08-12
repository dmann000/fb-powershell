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
        The ID of the array connection to remove. Accepts pipeline input by property name. Legal
        on its own and alongside -RemoteId.
    .PARAMETER RemoteId
        The ID of the REMOTE array whose connection to remove. A selector in its own right, and
        combinable with -Id. Mutually exclusive with -RemoteName: the API declares remote_names
        and remote_ids as alternative ways to name the same remote dimension.
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
        Remove-PfbArrayConnection -RemoteId '10314f42-020d-7080-8013-000133810cd0'

        Removes the connection to the remote array with the specified remote array id. DELETE
        /array-connections documents remote_ids as a selector, so no other selector is needed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByRemoteName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$RemoteName,

        [Parameter(ParameterSetName = 'ById', Mandatory, ValueFromPipelineByPropertyName)] [string]$Id,

        # remote_ids is a selector and cannot be combined with remote_names. -RemoteId is
        # mandatory in its own set so it can select alone, and optional in ById so ids +
        # remote_ids stays legal. It is -RemoteId, not -Id, that spans the two sets on purpose:
        # mirroring -Id into ByRemoteId instead costs -Id the ByPropertyName binding pass, so a
        # piped connection object coerces whole into -RemoteName -- true whether the mirrored
        # declaration is mandatory or optional, and mandatory would additionally stop -RemoteId
        # selecting alone. Verified on both PowerShell editions.
        [Parameter(ParameterSetName = 'ById')]
        [Parameter(ParameterSetName = 'ByRemoteId', Mandatory)]
        [string]$RemoteId,

        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($RemoteName) { Assert-PfbRemoteNameNotCoerced -Value $RemoteName }
        $target = if ($RemoteName) { $RemoteName } elseif ($RemoteId) { $RemoteId } else { $Id }
        $queryParams = @{}
        if ($RemoteName) { $queryParams['remote_names'] = $RemoteName }
        if ($Id) { $queryParams['ids'] = $Id }
        # remote_ids is a selector and cannot be combined with remote_names.
        if ($RemoteId) { $queryParams['remote_ids'] = $RemoteId }
        if ($PSCmdlet.ShouldProcess($target, 'Remove array connection')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'array-connections' -QueryParams $queryParams
        }
    }
}
