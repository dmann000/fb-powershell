function Update-PfbSshCaPolicy {
    <#
    .SYNOPSIS
        Updates an existing SSH certificate authority policy on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbSshCaPolicy cmdlet modifies attributes of an existing SSH CA policy on
        the connected Everpure FlashBlade. The policy can be identified by name or ID.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the SSH CA policy to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the SSH CA policy to update.
    .PARAMETER Enabled
        If true, the policy is enabled.
    .PARAMETER Location
        Reference to the array where the policy is defined.
    .PARAMETER NewName
        A new name for the SSH CA policy.
    .PARAMETER SigningAuthority
        A reference to the authority that will digitally sign user SSH certificates that
        will be used to access the system.
    .PARAMETER StaticAuthorizedPrincipals
        If not specified, users affected by this policy can only log into the system when
        they present an SSH certificate containing their own username as a principal.
    .PARAMETER Attributes
        A hashtable of SSH CA policy attributes to modify. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSshCaPolicy -Name "ssh-ca-prod" -Enabled $true

        Enables the SSH CA policy named "ssh-ca-prod" using a typed parameter.
    .EXAMPLE
        Update-PfbSshCaPolicy -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ public_key = "ssh-rsa NEW..." }

        Updates the public key of the SSH CA policy by ID.
    .EXAMPLE
        Update-PfbSshCaPolicy -Name "ssh-ca-prod" -Attributes @{ enabled = $false } -WhatIf

        Shows what would happen without actually updating the policy.
    .NOTES
        <!-- PfbContext: generated from Data/PfbCapabilityMap.json contextScope. Do not edit. -->
        Context requirement (PATCH /ssh-certificate-authority-policies): the context scope for this endpoint is not
        recorded in the capability map, so the module will not pre-validate a context
        for it. A fleet or array context may still be required by the array itself; if
        a call fails with a context error, set one with Set-PfbContext or scope the
        call with Invoke-PfbInContext.
        <!-- /PfbContext -->
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
        [Nullable[bool]]$Enabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Location,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$SigningAuthority,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$StaticAuthorizedPrincipals,

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
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Enabled'))          { $body['enabled']           = $Enabled }
            if ($PSBoundParameters.ContainsKey('Location'))         { $body['location']          = @{ name = $Location } }
            if ($PSBoundParameters.ContainsKey('NewName'))          { $body['name']               = $NewName }
            if ($PSBoundParameters.ContainsKey('SigningAuthority')) { $body['signing_authority']  = @{ name = $SigningAuthority } }
            if ($PSBoundParameters.ContainsKey('StaticAuthorizedPrincipals')) {
                $body['static_authorized_principals'] = @($StaticAuthorizedPrincipals)
            }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update SSH CA policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'ssh-certificate-authority-policies' -Body $body -QueryParams $queryParams
        }
    }
}
