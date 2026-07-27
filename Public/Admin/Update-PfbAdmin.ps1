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
            $body = @{}
            if ($AuthorizationModel) { $body['authorization_model'] = $AuthorizationModel }
            if ($OldPassword)        { $body['old_password']        = $OldPassword }
            if ($Password)           { $body['password']            = $Password }
            if ($PublicKey)          { $body['public_key']          = $PublicKey }

            # Constraint 2: explicit $false must still be sent. The [Nullable[bool]] type plus
            # this ContainsKey guard is what achieves that -- constraint 7 forbids a [bool]
            # cast here, which would break the wire-name trace and buys nothing.
            if ($PSBoundParameters.ContainsKey('Locked')) { $body['locked'] = $Locked }

            # Constraint 8(b): management_access_policies is an ARRAY OF REFERENCES (item
            # schema is {id, name, resource_type}), so the parameter is [string[]] and the
            # projection is assigned INLINE -- constraint 7 forbids a $policyRefs local.
            if ($ManagementAccessPolicies) {
                $body['management_access_policies'] = @($ManagementAccessPolicies | ForEach-Object { @{ name = $_ } })
            }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update admin')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'admins' -Body $body -QueryParams $queryParams
        }
    }
}
