function Update-PfbAdmin {
    <#
    .SYNOPSIS
        Updates a FlashBlade administrator account.
    .DESCRIPTION
        The Update-PfbAdmin cmdlet modifies attributes of an existing administrator account
        on the connected Everpure FlashBlade. The target administrator can be identified
        by name or ID. Common updates include password resets and access-policy changes.
        Supports pipeline input and ShouldProcess for confirmation prompts.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the administrator account to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the administrator account to update.
    .PARAMETER AuthorizationModel
        The location for access policies mapping.
    .PARAMETER Locked
        If set to $false, the specified user is unlocked.
    .PARAMETER ManagementAccessPolicies
        Names of the management access policies associated with the statically-authorized
        administrator.
    .PARAMETER OldPassword
        Old user password.
    .PARAMETER Password
        New user password.
    .PARAMETER PublicKey
        Public key for SSH access.
    .PARAMETER Attributes
        A hashtable of administrator attributes to modify. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbAdmin -Name "ops-admin" -Password "N3wP@ssw0rd!" -Locked $false

        Resets the password for "ops-admin" and unlocks the account using typed parameters.
    .EXAMPLE
        Update-PfbAdmin -Name "ops-admin" -ManagementAccessPolicies "array-admin","readonly"

        Assigns two management access policies to the administrator named "ops-admin".
    .EXAMPLE
        Update-PfbAdmin -Name "ops-admin" -Attributes @{ password = "N3wP@ssw0rd!" }

        Updates the password for the administrator account named "ops-admin".
    .EXAMPLE
        Update-PfbAdmin -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ locked = $false }

        Unlocks the administrator identified by ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$AuthorizationModel,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$Locked,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$ManagementAccessPolicies,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$OldPassword,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Password,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$PublicKey,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # EVERY value-carrying parameter -- body OR query -- is guarded by
            # $PSBoundParameters.ContainsKey, never by truthiness. `if ($X)` silently discards
            # any legitimate falsy value the caller explicitly supplied: $false, 0, '' and an
            # empty array all fail a truthiness test. So `-Locked $false` would never unlock,
            # an integer field could never be set to a meaningful 0, and
            # `-ManagementAccessPolicies @()` could never clear a list. ContainsKey asks the
            # only correct question -- did the caller supply this parameter at all?
            #
            # The one exemption is a MANDATORY [string] selector like -Name/-Id above: the
            # binder rejects '' for those before any guard runs, so their falsy branch is
            # unreachable and `if ($Name)` is safe. That exemption is about mandatory-ness,
            # not about being a query parameter -- an OPTIONAL query parameter still needs
            # ContainsKey (see -Timeout in New-PfbApiToken.ps1).
            #
            # No [bool] cast on $Locked either: constraint 7 forbids it (it breaks the
            # wire-name trace) and [Nullable[bool]] + ContainsKey already sends an explicit
            # $false correctly.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('AuthorizationModel')) { $body['authorization_model'] = $AuthorizationModel }
            if ($PSBoundParameters.ContainsKey('Locked'))             { $body['locked']              = $Locked }
            if ($PSBoundParameters.ContainsKey('OldPassword'))        { $body['old_password']        = $OldPassword }
            if ($PSBoundParameters.ContainsKey('Password'))           { $body['password']            = $Password }
            if ($PSBoundParameters.ContainsKey('PublicKey'))          { $body['public_key']          = $PublicKey }

            # Constraint 8(b): management_access_policies is an ARRAY OF REFERENCES (item
            # schema is {id, name, resource_type}), so the parameter is [string[]] and the
            # projection is assigned INLINE -- constraint 7 forbids a $policyRefs local.
            if ($PSBoundParameters.ContainsKey('ManagementAccessPolicies')) {
                $body['management_access_policies'] = @($ManagementAccessPolicies | ForEach-Object { @{ name = $_ } })
            }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update admin')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'admins' -Body $body -QueryParams $queryParams
        }
    }
}
