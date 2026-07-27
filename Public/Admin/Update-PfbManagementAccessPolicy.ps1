function Update-PfbManagementAccessPolicy {
    <#
    .SYNOPSIS
        Updates an existing management access policy on the FlashBlade.
    .DESCRIPTION
        The Update-PfbManagementAccessPolicy cmdlet modifies attributes of an existing management
        access policy on the connected Everpure FlashBlade. The target policy can be identified
        by name or ID. Supports ShouldProcess for confirmation prompts.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the management access policy to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the management access policy to update.
    .PARAMETER AggregationStrategy
        When this is set to `least-common-permissions`, any users to whom this policy applies
        can receive no access rights exceeding those defined in this policy's capability and
        resource. When this is set to `all-permissions`, any users to whom this policy applies
        are capable of receiving additional access rights from other policies that apply to
        them.
    .PARAMETER Enabled
        If $true, the policy is enabled.
    .PARAMETER Location
        Name of the array where the policy is defined.
    .PARAMETER PolicyName
        A new user-specified name for the policy. Named -PolicyName rather than -Name because
        -Name already identifies which policy to update.
    .PARAMETER Rules
        All of the rules that are part of this policy, in evaluation order. Each rule is a
        hashtable with `role` and `scope` sub-objects, for example
        @{ role = @{ name = 'viewer' }; scope = @{ name = 'array-1'; resource_type = 'arrays' } }.
    .PARAMETER Attributes
        A hashtable of policy attributes to modify. Mutually exclusive with the individual
        typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbManagementAccessPolicy -Name "ops-policy" -Enabled $true -AggregationStrategy "least-common-permissions"

        Enables the "ops-policy" management access policy and restricts its aggregation
        strategy, using typed parameters.
    .EXAMPLE
        Update-PfbManagementAccessPolicy -Name "ops-policy" -Rules @(
            @{ role = @{ name = "viewer" }; scope = @{ name = "array-1"; resource_type = "arrays" } }
        )

        Replaces the policy's rule list with a single viewer rule scoped to "array-1".
    .EXAMPLE
        Update-PfbManagementAccessPolicy -Id "abc12345-6789-0abc-def0-123456789abc" -Attributes @{ enabled = $true }

        Enables the management access policy identified by ID.
    .EXAMPLE
        Update-PfbManagementAccessPolicy -Name "test-policy" -Attributes @{ } -WhatIf

        Shows what would happen if the policy were updated without making changes.
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
        [string]$AggregationStrategy,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$Enabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Location,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$PolicyName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable[]]$Rules,

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
            if ($AggregationStrategy) { $body['aggregation_strategy'] = $AggregationStrategy }
            if ($PolicyName)          { $body['name']                 = $PolicyName }

            # Constraint 2: explicit $false must still be sent. The [Nullable[bool]] type plus
            # this ContainsKey guard is what achieves that -- constraint 7 forbids a [bool]
            # cast here, which would break the wire-name trace and buys nothing.
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = $Enabled }

            # Constraint 8(a): location is a SCALAR REFERENCE (_fixedReference, properties are
            # exactly {id, name, resource_type}), so the parameter is [string] and the
            # reference object is built INLINE -- constraint 7 forbids a $locationRef local.
            if ($Location) { $body['location'] = @{ name = $Location } }

            # Constraint 8(c): rules is an array of COMPOSITE objects, not references -- the
            # item schema (ManagementAccessPolicyRuleInPolicy) carries `role`, `scope` and
            # `index` beyond {id, name, resource_type}, and its own `name` is readOnly. So it
            # is passed straight through rather than projected into @{ name = ... }, which
            # would write a field the schema does not accept.
            if ($Rules) { $body['rules'] = @($Rules) }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update management access policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'management-access-policies' -Body $body -QueryParams $queryParams
        }
    }
}
