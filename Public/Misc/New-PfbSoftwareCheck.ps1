function New-PfbSoftwareCheck {
    <#
    .SYNOPSIS
        Initiates a software check on a FlashBlade array.
    .DESCRIPTION
        The New-PfbSoftwareCheck cmdlet initiates a new pre-upgrade software check on the
        connected Pure Storage FlashBlade to identify potential issues before upgrading.
    .PARAMETER Attributes
        A hashtable of software check attributes to configure.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSoftwareCheck -Attributes @{}

        Initiates a software check with default settings.
    .EXAMPLE
        New-PfbSoftwareCheck -Attributes @{ software_name = "purity-fb" }

        Initiates a software check for the specified software.
    .EXAMPLE
        New-PfbSoftwareCheck -Attributes @{} -WhatIf

        Shows what would happen without actually running the check.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Initiate software check')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'software-check' -Body $Attributes
    }
}
