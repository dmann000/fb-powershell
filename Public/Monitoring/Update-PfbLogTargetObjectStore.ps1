function Update-PfbLogTargetObjectStore {
    <#
    .SYNOPSIS
        Updates a log-target object-store configuration on the FlashBlade.
    .DESCRIPTION
        The Update-PfbLogTargetObjectStore cmdlet modifies a log-target object-store
        configuration on the connected Everpure FlashBlade. Identify the target by
        name or ID and supply the changed properties via Attributes or individual parameters.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the log-target object store to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the log-target object store to update.
    .PARAMETER Bucket
        Reference to the bucket where audit logs will be stored.
    .PARAMETER LogNamePrefix
        The prefix of the audit log object.
    .PARAMETER LogRotate
        The threshold after which the audit log object will be rotated.
    .PARAMETER NewName
        A new user-specified name for the log target. Named -NewName rather than -Name
        because -Name already identifies which log target to update.
    .PARAMETER Attributes
        A hashtable of attributes to update on the configuration. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbLogTargetObjectStore -Name "log-obj-target1" -LogNamePrefix @{ prefix = 's3auditlog' }

        Updates the audit-log object-name prefix on the log-target object-store configuration
        using a typed parameter.
    .EXAMPLE
        Update-PfbLogTargetObjectStore -Id "12345" -Attributes @{ enabled = $true }

        Enables the log-target object store identified by ID.
    .EXAMPLE
        Update-PfbLogTargetObjectStore -Name "log-obj-target1" -Bucket 'new-bucket'

        Updates the bucket reference on the log-target object store using a typed parameter.
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
        [string]$Bucket,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable]$LogNamePrefix,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable]$LogRotate,

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
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Every value-carrying parameter is guarded by ContainsKey, never by truthiness --
            # see the canonical explanation in Update-PfbAdmin.ps1.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('NewName')) { $body['name'] = $NewName }

            # Constraint 8(a): bucket is a SCALAR REFERENCE (item schema is
            # {id, name, resource_type}), so the parameter is [string] taking the name and the
            # projection is assigned INLINE -- constraint 7 forbids an intermediate local.
            if ($PSBoundParameters.ContainsKey('Bucket')) { $body['bucket'] = @{ name = $Bucket } }

            # Constraint 8(c): log_name_prefix and log_rotate are COMPOSITE sub-objects
            # (_auditLogNamePrefix, _auditLogRotate), not references -- neither has a `name`
            # property, so projecting them into @{ name = ... } would write a field the schema
            # does not have. Pass them straight through.
            if ($PSBoundParameters.ContainsKey('LogNamePrefix')) { $body['log_name_prefix'] = $LogNamePrefix }
            if ($PSBoundParameters.ContainsKey('LogRotate'))     { $body['log_rotate']      = $LogRotate }
        }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update log-target object store')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'log-targets/object-store' -Body $body -QueryParams $queryParams
        }
    }
}
