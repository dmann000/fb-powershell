function New-PfbSupportDiagnostics {
    <#
    .SYNOPSIS
        Creates a new support diagnostics job on a FlashBlade array.
    .DESCRIPTION
        The New-PfbSupportDiagnostics cmdlet initiates a new support diagnostics collection
        job on the connected Pure Storage FlashBlade. The diagnostics bundle collects system
        information useful for troubleshooting and support cases.
    .PARAMETER Attributes
        A hashtable of diagnostics job attributes to configure.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSupportDiagnostics -Attributes @{}

        Creates a new support diagnostics job with default settings.
    .EXAMPLE
        New-PfbSupportDiagnostics -Attributes @{ description = "Case 12345" }

        Creates a new diagnostics job with a description referencing a support case.
    .EXAMPLE
        New-PfbSupportDiagnostics -Attributes @{} -WhatIf

        Shows what would happen without actually creating the diagnostics job.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Create support diagnostics job')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'support-diagnostics' -Body $Attributes
    }
}
