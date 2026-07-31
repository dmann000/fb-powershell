function Update-PfbTarget {
    <#
    .SYNOPSIS
        Updates an existing replication target on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbTarget cmdlet modifies attributes of an existing replication target on the
        connected Pure Storage FlashBlade. The target can be identified by name or ID. Common
        updates include changing the address, credentials, or connection settings. Supports
        pipeline input and ShouldProcess for confirmation prompts.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the replication target to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the replication target to update.
    .PARAMETER Address
        IP address or FQDN of the target system.
    .PARAMETER CaCertificateGroup
        The group of CA certificates that can be used, in addition to well-known Certificate
        Authority certificates, in order to establish a secure connection to the target system.
    .PARAMETER NewName
        A user-specified name for the target. Named -NewName rather than -Name because -Name
        already identifies which target to update.
    .PARAMETER Attributes
        A hashtable of target attributes to modify. Mutually exclusive with the individual
        typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbTarget -Name "s3-target-aws" -Attributes @{ address = "s3.us-east-1.amazonaws.com" }

        Updates the address for the replication target named "s3-target-aws".
    .EXAMPLE
        Update-PfbTarget -Name "remote-fb-dc2" -Attributes @{ connection_key = "new-key-456" }

        Updates the connection key for the "remote-fb-dc2" replication target.
    .EXAMPLE
        Update-PfbTarget -Id "10314f42-020d-7080-8013-000ddt400099" -Attributes @{ enabled = $true }

        Enables the replication target identified by the specified ID.
    .EXAMPLE
        Update-PfbTarget -Name "s3-target-aws" -Address "s3.us-east-1.amazonaws.com" -NewName "s3-target-renamed"

        Updates the address and renames the replication target using typed parameters.
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
        [string]$Address,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$CaCertificateGroup,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

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
            if ($PSBoundParameters.ContainsKey('Address')) { $body['address'] = $Address }

            # Constraint 8(a): ca_certificate_group is a SCALAR reference (item schema is
            # {id, name, resource_type}), so the parameter is [string] and the projection is
            # assigned inline as a name-reference hashtable.
            if ($PSBoundParameters.ContainsKey('CaCertificateGroup')) { $body['ca_certificate_group'] = @{ name = $CaCertificateGroup } }
            if ($PSBoundParameters.ContainsKey('NewName'))            { $body['name'] = $NewName }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update target')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'targets' -Body $body -QueryParams $queryParams
        }
    }
}
