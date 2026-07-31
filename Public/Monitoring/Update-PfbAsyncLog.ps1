function Update-PfbAsyncLog {
    <#
    .SYNOPSIS
        Updates an asynchronous log collection job on the FlashBlade.
    .DESCRIPTION
        The Update-PfbAsyncLog cmdlet modifies an asynchronous log collection job on the
        connected Everpure FlashBlade. Identify the job by name or ID and supply the
        changed properties via Attributes or individual parameters.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the async log job to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the async log job to update.
    .PARAMETER EndTime
        When the time window ends (in milliseconds since epoch).
    .PARAMETER HardwareComponents
        All of the hardware components for which logs are being processed.
    .PARAMETER StartTime
        When the time window starts (in milliseconds since epoch).
    .PARAMETER Attributes
        A hashtable of attributes to update on the async log job. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbAsyncLog -Name "log-job-1" -StartTime 1700000000000 -EndTime 1700003600000

        Sets the processing time window for the async log job named "log-job-1" using typed
        parameters.
    .EXAMPLE
        Update-PfbAsyncLog -Id "12345" -Attributes @{ status = 'cancelled' }

        Cancels the async log job identified by ID.
    .EXAMPLE
        Update-PfbAsyncLog -Name "log-job-1" -Attributes @{ keep_until = 1700000000000 }

        Updates the retention time for the specified async log job.
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
        [long]$EndTime,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$HardwareComponents,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$StartTime,

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
            if ($PSBoundParameters.ContainsKey('EndTime'))   { $body['end_time']   = $EndTime }
            if ($PSBoundParameters.ContainsKey('StartTime')) { $body['start_time'] = $StartTime }

            # Constraint 8(b): hardware_components is an ARRAY OF REFERENCES (item schema is
            # {id, name, resource_type}), so the parameter is [string[]] and the projection is
            # assigned INLINE -- constraint 7 forbids an intermediate local.
            if ($PSBoundParameters.ContainsKey('HardwareComponents')) {
                $body['hardware_components'] = @($HardwareComponents | ForEach-Object { @{ name = $_ } })
            }
        }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update async log job')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'logs-async' -Body $body -QueryParams $queryParams
        }
    }
}
