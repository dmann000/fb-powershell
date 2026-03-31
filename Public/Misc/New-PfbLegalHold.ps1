function New-PfbLegalHold {
    <#
    .SYNOPSIS
        Creates a new legal hold on the FlashBlade.
    .DESCRIPTION
        The New-PfbLegalHold cmdlet creates a legal hold on the connected Pure Storage
        FlashBlade. Use the Attributes parameter to supply a hashtable of hold properties,
        or provide individual parameters.
    .PARAMETER Name
        The name of the legal hold to create.
    .PARAMETER Attributes
        A hashtable of additional attributes for the legal hold body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbLegalHold -Name "litigation-hold-2024"

        Creates a new legal hold named "litigation-hold-2024".
    .EXAMPLE
        New-PfbLegalHold -Name "litigation-hold-2024" -Attributes @{ description = 'Q4 litigation' }

        Creates a new legal hold with a description attribute.
    .EXAMPLE
        New-PfbLegalHold -Name "sec-investigation" -Attributes @{ enabled = $true }

        Creates an enabled legal hold for SEC investigation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create legal hold')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'legal-holds' -Body $body -QueryParams $queryParams
    }
}
