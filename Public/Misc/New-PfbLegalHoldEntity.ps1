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
    .PARAMETER FileSystemIds
        The IDs of the file systems to place under legal hold.
    .PARAMETER FileSystemNames
        The names of the file systems to place under legal hold.
    .PARAMETER Ids
        The IDs of the held entities to create.
    .PARAMETER Names
        The names of the held entities to create.
    .PARAMETER Paths
        The paths to place under legal hold.
    .PARAMETER Recursive
        If set to `true`, the legal hold is applied recursively to the specified path or
        file system.
    .PARAMETER Attributes
        A hashtable of additional attributes for the held-entity body. `POST
        /legal-holds/held-entities` accepts no request body, so nothing supplied here is
        sent to the array. Use the typed query parameters above instead.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbLegalHoldEntity -HoldName "litigation-hold-2024" -MemberName "fs1"

        Places file system "fs1" under the legal hold "litigation-hold-2024".
    .EXAMPLE
        New-PfbLegalHoldEntity -HoldName "litigation-hold-2024" -Paths "/dir1" -Recursive $true

        Recursively places everything under "/dir1" under the specified legal hold.
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
        [string[]]$FileSystemIds,

        [Parameter()]
        [string[]]$FileSystemNames,

        [Parameter()]
        [string[]]$Ids,

        [Parameter()]
        [string[]]$Names,

        [Parameter()]
        [string[]]$Paths,

        [Parameter()]
        [Nullable[bool]]$Recursive,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    # POST /legal-holds/held-entities accepts no request body at all -- everything this
    # endpoint accepts is a query parameter (see New-PfbApiToken.ps1 for the identical shape).
    $body = if ($Attributes) { $Attributes } else { @{} }

    $queryParams = @{}
    if ($HoldName)   { $queryParams['hold_names']   = $HoldName }
    if ($MemberName) { $queryParams['member_names'] = $MemberName }

    # Every newly added query parameter is guarded by ContainsKey, never truthiness -- see the
    # canonical explanation in Update-PfbAdmin.ps1. An array field's `@()` must still reach the
    # wire so a caller can send an explicitly empty list.
    if ($PSBoundParameters.ContainsKey('FileSystemIds'))   { $queryParams['file_system_ids']   = $FileSystemIds -join ',' }
    if ($PSBoundParameters.ContainsKey('FileSystemNames')) { $queryParams['file_system_names'] = $FileSystemNames -join ',' }
    if ($PSBoundParameters.ContainsKey('Ids'))              { $queryParams['ids']               = $Ids -join ',' }
    if ($PSBoundParameters.ContainsKey('Names'))            { $queryParams['names']             = $Names -join ',' }
    if ($PSBoundParameters.ContainsKey('Paths'))            { $queryParams['paths']             = $Paths -join ',' }
    if ($PSBoundParameters.ContainsKey('Recursive'))        { $queryParams['recursive']         = $Recursive }

    $target = "${HoldName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Add legal hold entity')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'legal-holds/held-entities' -Body $body -QueryParams $queryParams
    }
}
