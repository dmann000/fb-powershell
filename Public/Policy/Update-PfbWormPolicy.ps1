function Update-PfbWormPolicy {
    <#
    .SYNOPSIS
        Updates an existing WORM data policy on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbWormPolicy cmdlet modifies attributes of an existing WORM data policy
        on the connected Everpure FlashBlade. The policy can be identified by name or ID.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value. This cmdlet is compliance-critical: -Mode,
        -RetentionLock, -MinRetention, -MaxRetention and -DefaultRetention govern WORM
        retention-lock behavior. No additional mutual-exclusion guard is added beyond the
        parameter sets themselves -- they already make a silent override impossible.
    .PARAMETER Name
        The name of the WORM policy to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the WORM policy to update.
    .PARAMETER DefaultRetention
        Default retention period, in milliseconds.
    .PARAMETER Enabled
        If true, the policy is enabled.
    .PARAMETER Location
        Reference to the array where the policy is defined.
    .PARAMETER MaxRetention
        Maximum retention period, in milliseconds.
    .PARAMETER MinRetention
        Minimum retention period, in milliseconds.
    .PARAMETER Mode
        The type of the retention lock.
    .PARAMETER RetentionLock
        If set to `locked`, then the value of retention attributes or policy attributes
        are not allowed to change.
    .PARAMETER Attributes
        A hashtable of WORM policy attributes to modify. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbWormPolicy -Name "worm-compliance" -MinRetention 7776000000

        Updates the minimum retention period for the WORM policy using a typed parameter.
    .EXAMPLE
        Update-PfbWormPolicy -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ enabled = $true }

        Enables the WORM policy by ID.
    .EXAMPLE
        Update-PfbWormPolicy -Name "worm-compliance" -Attributes @{} -WhatIf

        Shows what would happen without actually updating the policy.
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
        [long]$DefaultRetention,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$Enabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Location,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$MaxRetention,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$MinRetention,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Mode,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [ValidateSet('unlocked', 'locked')]
        [string]$RetentionLock,

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
        if ($Id) { $queryParams['ids'] = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Constraint 2: default_retention/max_retention/min_retention are integer body
            # fields, guarded with ContainsKey (not truthiness) so an explicit 0 reaches the
            # wire. Constraint 5: no extra mutual-exclusion throw is added here even though
            # these fields are compliance-critical -- the parameter sets above already make
            # a silent override across -Attributes and the typed parameters impossible.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('DefaultRetention')) { $body['default_retention'] = $DefaultRetention }
            if ($PSBoundParameters.ContainsKey('Enabled'))          { $body['enabled']            = $Enabled }
            if ($PSBoundParameters.ContainsKey('Location'))         { $body['location']           = @{ name = $Location } }
            if ($PSBoundParameters.ContainsKey('MaxRetention'))     { $body['max_retention']       = $MaxRetention }
            if ($PSBoundParameters.ContainsKey('MinRetention'))     { $body['min_retention']       = $MinRetention }
            if ($PSBoundParameters.ContainsKey('Mode'))             { $body['mode']                = $Mode }
            if ($PSBoundParameters.ContainsKey('RetentionLock'))    { $body['retention_lock']      = $RetentionLock }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update WORM data policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'worm-data-policies' -Body $body -QueryParams $queryParams
        }
    }
}
