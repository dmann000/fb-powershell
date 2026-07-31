function Update-PfbLegalHoldEntity {
    <#
    .SYNOPSIS
        Updates a held entity under a legal hold on the FlashBlade.
    .DESCRIPTION
        The Update-PfbLegalHoldEntity cmdlet modifies the properties of an entity that is
        subject to a legal hold on the connected Pure Storage FlashBlade. Identify the
        held entity by name and supply the changed properties via Attributes.
    .PARAMETER Name
        The name of the held entity to update.
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
        If set to `true`, the held entity is released from its legal hold.
    .PARAMETER Attributes
        A hashtable of attributes to update on the held entity. `PATCH
        /legal-holds/held-entities` accepts no request body, so nothing supplied here is sent
        to the array. Use the typed query parameters above instead.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbLegalHoldEntity -Name "fs1" -Released $true

        Releases the held entity named "fs1" from its legal hold.
    .EXAMPLE
        Update-PfbLegalHoldEntity -Name "bucket1" -Recursive $false

        Updates the held entity named "bucket1" without applying the change recursively.
    .EXAMPLE
        Update-PfbLegalHoldEntity -Name "fs1" -Attributes @{ hold_type = 'litigation' }

        Updates the held entity using a raw attributes hashtable.
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

        [Parameter()]
        [Nullable[bool]]$Released,

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
        if ($PSBoundParameters.ContainsKey('Released'))         { $queryParams['released']          = $Released }

        if ($PSCmdlet.ShouldProcess($Name, 'Update legal hold entity')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'legal-holds/held-entities' -Body $body -QueryParams $queryParams
        }
    }
}
