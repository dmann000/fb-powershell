function New-PfbArrayConnection {
    <#
    .SYNOPSIS
        Creates a new array connection for replication.
    .DESCRIPTION
        The New-PfbArrayConnection cmdlet establishes a new replication connection between the
        local Pure Storage FlashBlade and a remote array. A valid management address and
        connection key from the remote array are required. The connection can be created using
        individual parameters or a single Attributes hashtable. Supports ShouldProcess.
    .PARAMETER ManagementAddress
        The management IP address or FQDN of the remote FlashBlade array.
    .PARAMETER ReplicationAddress
        The replication IP address or FQDN of the remote FlashBlade array.
    .PARAMETER ConnectionKey
        The connection key obtained from the remote FlashBlade array.
    .PARAMETER Attributes
        A hashtable of connection attributes. When specified, individual parameters are ignored.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbArrayConnection -ManagementAddress "remote-fb.example.com" -ConnectionKey "1fc6297a-5183-4b7a-8d58-0182af1a2b64"

        Creates an array connection to the remote FlashBlade using its management address and connection key.
    .EXAMPLE
        New-PfbArrayConnection -Attributes @{ management_address = "10.0.2.100"; replication_addresses = @("10.0.3.100"); connection_key = "abc-123-def" }

        Creates an array connection using an Attributes hashtable with explicit replication address.
    .EXAMPLE
        New-PfbArrayConnection -ManagementAddress "fb-dr.example.com" -ReplicationAddress "10.0.4.100" -ConnectionKey "key-456" -WhatIf

        Shows what would happen if the array connection were created without actually creating it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()] [string]$ManagementAddress,
        [Parameter()] [string]$ReplicationAddress,
        [Parameter()] [string]$ConnectionKey,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($ManagementAddress)  { $body['management_address'] = $ManagementAddress }
        if ($ReplicationAddress) { $body['replication_addresses'] = @($ReplicationAddress) }
        if ($ConnectionKey)      { $body['connection_key'] = $ConnectionKey }
    }
    $target = if ($ManagementAddress) { $ManagementAddress } else { 'array connection' }
    if ($PSCmdlet.ShouldProcess($target, 'Create array connection')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'array-connections' -Body $body
    }
}
