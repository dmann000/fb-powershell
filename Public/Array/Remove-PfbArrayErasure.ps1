function Remove-PfbArrayErasure {
    <#
    .SYNOPSIS
        Removes an array erasure job from a FlashBlade.
    .DESCRIPTION
        The Remove-PfbArrayErasure cmdlet deletes an array erasure job from the connected
        Pure Storage FlashBlade. This cmdlet has a high confirm impact.
    .PARAMETER Attributes
        A hashtable identifying the erasure job to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbArrayErasure

        Removes the array erasure job after prompting for confirmation.
    .EXAMPLE
        Remove-PfbArrayErasure -Confirm:$false

        Removes the array erasure job without prompting.
    .EXAMPLE
        Remove-PfbArrayErasure -WhatIf

        Shows what would happen without actually removing the erasure job.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Remove array erasure job')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'arrays/erasures'
    }
}
