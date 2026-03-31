function New-PfbArrayErasure {
    <#
    .SYNOPSIS
        Creates a new array erasure job on a FlashBlade.
    .DESCRIPTION
        The New-PfbArrayErasure cmdlet initiates a new data erasure job on the connected
        Pure Storage FlashBlade. This securely wipes data from the array.
    .PARAMETER Attributes
        A hashtable of erasure job attributes to configure.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbArrayErasure -Attributes @{}

        Creates a new erasure job with default settings.
    .EXAMPLE
        New-PfbArrayErasure -Attributes @{ type = "full" }

        Creates a full erasure job.
    .EXAMPLE
        New-PfbArrayErasure -Attributes @{} -WhatIf

        Shows what would happen without actually creating the erasure job.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Create array erasure job')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'arrays/erasures' -Body $Attributes
    }
}
