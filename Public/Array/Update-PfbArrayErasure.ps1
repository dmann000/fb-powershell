function Update-PfbArrayErasure {
    <#
    .SYNOPSIS
        Updates an array erasure job on a FlashBlade.
    .DESCRIPTION
        The Update-PfbArrayErasure cmdlet modifies an existing array erasure job on the
        connected Pure Storage FlashBlade.
    .PARAMETER Attributes
        A hashtable of erasure job attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbArrayErasure -Attributes @{ status = "cancelled" }

        Cancels an active erasure job.
    .EXAMPLE
        Update-PfbArrayErasure -Attributes @{} -WhatIf

        Shows what would happen without actually updating the erasure job.
    .EXAMPLE
        Update-PfbArrayErasure -Attributes @{ status = "paused" }

        Pauses an active erasure job.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Update array erasure job')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'arrays/erasures' -Body $Attributes
    }
}
