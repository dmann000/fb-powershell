function New-PfbLegalHoldEntity {
    <#
    .SYNOPSIS
        Adds an entity to a legal hold on the FlashBlade.
    .DESCRIPTION
        The New-PfbLegalHoldEntity cmdlet associates an entity (file system, bucket, etc.)
        with a legal hold on the connected Pure Storage FlashBlade. Identify the entity by
        file system, ID, name, or path, and optionally supply additional attributes.

        Whole-branch review fix: -HoldName/-MemberName (`hold_names`/`member_names`) are
        removed -- `POST /legal-holds/held-entities` has no such query parameters in any
        cached spec version (2.4-2.28), so they could never have had any effect. -Names and
        -FileSystemNames (added by this task, real and spec-backed) already cover the same
        job these were attempting.
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
        New-PfbLegalHoldEntity -Names "litigation-hold-2024" -FileSystemNames "fs1"

        Places file system "fs1" under the legal hold "litigation-hold-2024".
    .EXAMPLE
        New-PfbLegalHoldEntity -Names "litigation-hold-2024" -Paths "/dir1" -Recursive $true

        Recursively places everything under "/dir1" under the specified legal hold.
    .EXAMPLE
        New-PfbLegalHoldEntity -Names "sec-investigation" -FileSystemNames "bucket1" -Confirm:$false

        Adds a held entity without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
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

    # Every newly added query parameter is guarded by ContainsKey, never truthiness -- see the
    # canonical explanation in Update-PfbAdmin.ps1. An array field's `@()` must still reach the
    # wire so a caller can send an explicitly empty list.
    if ($PSBoundParameters.ContainsKey('FileSystemIds'))   { $queryParams['file_system_ids']   = $FileSystemIds -join ',' }
    if ($PSBoundParameters.ContainsKey('FileSystemNames')) { $queryParams['file_system_names'] = $FileSystemNames -join ',' }
    if ($PSBoundParameters.ContainsKey('Ids'))              { $queryParams['ids']               = $Ids -join ',' }
    if ($PSBoundParameters.ContainsKey('Names'))            { $queryParams['names']             = $Names -join ',' }
    if ($PSBoundParameters.ContainsKey('Paths'))            { $queryParams['paths']             = $Paths -join ',' }
    if ($PSBoundParameters.ContainsKey('Recursive'))        { $queryParams['recursive']         = $Recursive }

    $target = if ($PSBoundParameters.ContainsKey('Names')) { $Names -join ',' }
              elseif ($PSBoundParameters.ContainsKey('FileSystemNames')) { $FileSystemNames -join ',' }
              else { 'legal hold entity' }

    if ($PSCmdlet.ShouldProcess($target, 'Add legal hold entity')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'legal-holds/held-entities' -Body $body -QueryParams $queryParams
    }
}
