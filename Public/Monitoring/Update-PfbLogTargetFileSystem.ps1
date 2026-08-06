function Update-PfbLogTargetFileSystem {
    <#
    .SYNOPSIS
        Updates a log-target file-system configuration on the FlashBlade.
    .DESCRIPTION
        The Update-PfbLogTargetFileSystem cmdlet modifies a log-target file-system
        configuration on the connected Everpure FlashBlade. Identify the target by
        name or ID and supply the changed properties via Attributes or individual parameters.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the log-target file system to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the log-target file system to update.
    .PARAMETER FileSystem
        The target filesystem where audit logs will be stored.
    .PARAMETER KeepFor
        Specifies the period that audit logs are retained before they are deleted, in
        milliseconds.
    .PARAMETER KeepSize
        Specifies the maximum size of audit logs to be retained.
    .PARAMETER NewName
        A new user-specified name for the log target. Named -NewName rather than -Name
        because -Name already identifies which log target to update.
    .PARAMETER Attributes
        A hashtable of attributes to update on the configuration. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbLogTargetFileSystem -Name "log-fs-target1" -KeepFor 86400000

        Updates the audit-log retention period on the log-target file-system configuration
        using a typed parameter.
    .EXAMPLE
        Update-PfbLogTargetFileSystem -Id "12345" -Attributes @{ enabled = $true }

        Enables the log-target file system identified by ID.
    .EXAMPLE
        Update-PfbLogTargetFileSystem -Name "log-fs-target1" -FileSystem 'new-fs'

        Updates the underlying file system reference using a typed parameter.
    .NOTES
        <!-- PfbContext: generated from Data/PfbCapabilityMap.json contextScope. Do not edit. -->
        Context requirement (PATCH /log-targets/file-systems): the context scope for this endpoint is not
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
        [string]$FileSystem,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$KeepFor,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$KeepSize,

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
            if ($PSBoundParameters.ContainsKey('KeepFor'))  { $body['keep_for']  = $KeepFor }
            if ($PSBoundParameters.ContainsKey('KeepSize')) { $body['keep_size'] = $KeepSize }
            if ($PSBoundParameters.ContainsKey('NewName'))  { $body['name']      = $NewName }

            # Constraint 8(a): file_system is a SCALAR REFERENCE (item schema is
            # {id, name, resource_type}), so the parameter is [string] taking the name and the
            # projection is assigned INLINE -- constraint 7 forbids an intermediate local.
            if ($PSBoundParameters.ContainsKey('FileSystem')) { $body['file_system'] = @{ name = $FileSystem } }
        }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update log-target file system')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'log-targets/file-systems' -Body $body -QueryParams $queryParams
        }
    }
}
