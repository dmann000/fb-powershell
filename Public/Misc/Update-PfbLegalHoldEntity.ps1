function Update-PfbLegalHoldEntity {
    <#
    .SYNOPSIS
        Updates a held entity under a legal hold on the FlashBlade.
    .DESCRIPTION
        The Update-PfbLegalHoldEntity cmdlet applies or releases a legal hold over a
        file-system path on the connected Pure Storage FlashBlade. `released` is required
        by the API, so -Released must always be supplied: `$true` releases the hold,
        `$false` applies it.

        A held entity has no name of its own -- `LegalHoldHeldEntity` carries only
        `file_system`, `legal_hold`, `path` and `status` -- so it is addressed by the
        file system plus the path, together with -Recursive. Measured on a live array
        (Purity//FB 4.8.2, REST 2.26): a request naming only the hold is rejected with
        "Either names or ids query parameter is required", and one naming the file system
        and path but omitting -Recursive is rejected with "Can't apply or release legal
        holds to directories without the recursive flag provided". Both directions behave
        identically here, so a release is symmetric with an apply rather than special.
    .PARAMETER Name
        The name of the legal hold. Sent as `names`, which the endpoint declares but which
        does not on its own identify a held entity -- see the description above.
    .PARAMETER FileSystemIds
        The IDs of the file systems whose held entities to update.
    .PARAMETER FileSystemNames
        The names of the file systems whose held entities to update.
    .PARAMETER Ids
        The IDs of the held entities to update.
    .PARAMETER Paths
        The paths of the held entities to update.
    .PARAMETER Recursive
        If set to `true`, the update is applied recursively to the specified path or file
        system.
    .PARAMETER Released
        Required by the API on REST 2.17 and later. `$true` releases the held entity from its
        legal hold; `$false` applies or keeps the legal hold.
    .PARAMETER Attributes
        A hashtable of attributes to update on the held entity. `PATCH
        /legal-holds/held-entities` accepts no request body, so nothing supplied here is sent
        to the array. Use the typed query parameters above instead.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbLegalHoldEntity -Name 'pslivetest-hold-1' -FileSystemNames 'pslivetest-fs-1' -Paths '/' -Recursive $true -Released $true

        Releases the held entity named "pslivetest-hold-1" from its legal hold. The file-system
        name, path, and recursive flag are all required together for this release request.
    .EXAMPLE
        Update-PfbLegalHoldEntity -Name 'pslivetest-hold-1' -FileSystemNames 'pslivetest-fs-1' -Paths '/' -Recursive $true -Released $false

        Applies the legal hold to the same path. This is the release example with -Released
        flipped -- the two directions take the same arguments.
    .EXAMPLE
        Update-PfbLegalHoldEntity -Name 'pslivetest-hold-1' -FileSystemIds '10314f42-020d-7080-8013-000ddt400090' -Paths '/' -Recursive $true -Released $true

        Releases the hold identifying the file system by ID instead of by name. Note that
        `file_system_ids` refers to the file system, which has an ID; the held entity itself
        does not, so -Ids is not a substitute for this form.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string[]]$FileSystemIds,

        [Parameter()]
        [string[]]$FileSystemNames,

        [Parameter()]
        [string[]]$Ids,

        [Parameter()]
        [string[]]$Paths,

        [Parameter()]
        [Nullable[bool]]$Recursive,

        [Parameter(Mandatory)]
        [bool]$Released,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        # PATCH /legal-holds/held-entities accepts no request body at all -- everything this
        # endpoint accepts is a query parameter (see New-PfbApiToken.ps1 for the identical shape).
        $body = if ($Attributes) { $Attributes } else { @{} }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }

        # Every newly added query parameter is guarded by ContainsKey, never truthiness -- see
        # the canonical explanation in Update-PfbAdmin.ps1.
        if ($PSBoundParameters.ContainsKey('FileSystemIds'))   { $queryParams['file_system_ids']   = $FileSystemIds -join ',' }
        if ($PSBoundParameters.ContainsKey('FileSystemNames')) { $queryParams['file_system_names'] = $FileSystemNames -join ',' }
        if ($PSBoundParameters.ContainsKey('Ids'))              { $queryParams['ids']               = $Ids -join ',' }
        if ($PSBoundParameters.ContainsKey('Paths'))            { $queryParams['paths']             = $Paths -join ',' }
        if ($PSBoundParameters.ContainsKey('Recursive'))        { $queryParams['recursive']         = $Recursive }
        # Unlike optional parameters, released is required by the spec, so no legal request omits it;
        # the usual ContainsKey distinction between omitted and supplied as false cannot arise here.
        $queryParams['released'] = $Released

        if ($PSCmdlet.ShouldProcess($Name, 'Update legal hold entity')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'legal-holds/held-entities' -Body $body -QueryParams $queryParams
        }
    }
}
