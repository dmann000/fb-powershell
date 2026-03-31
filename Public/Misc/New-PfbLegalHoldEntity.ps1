function New-PfbLegalHoldEntity {
    <#
    .SYNOPSIS
        Adds an entity to a legal hold on the FlashBlade.
    .DESCRIPTION
        The New-PfbLegalHoldEntity cmdlet associates an entity (file system, bucket, etc.)
        with a legal hold on the connected Pure Storage FlashBlade. Identify the hold and
        member by name, and optionally supply additional attributes.
    .PARAMETER HoldName
        The name of the legal hold.
    .PARAMETER MemberName
        The name of the entity to place under legal hold.
    .PARAMETER Attributes
        A hashtable of additional attributes for the held-entity body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbLegalHoldEntity -HoldName "litigation-hold-2024" -MemberName "fs1"

        Places file system "fs1" under the legal hold "litigation-hold-2024".
    .EXAMPLE
        New-PfbLegalHoldEntity -HoldName "litigation-hold-2024" -MemberName "fs1" -Attributes @{ type = 'file-system' }

        Adds a held entity with explicit type attribute.
    .EXAMPLE
        New-PfbLegalHoldEntity -HoldName "sec-investigation" -MemberName "bucket1" -Confirm:$false

        Adds a held entity without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [string]$HoldName,

        [Parameter()]
        [string]$MemberName,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }

    $queryParams = @{}
    if ($HoldName)   { $queryParams['hold_names']   = $HoldName }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }

    $target = "${HoldName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Add legal hold entity')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'legal-holds/held-entities' -Body $body -QueryParams $queryParams
    }
}
