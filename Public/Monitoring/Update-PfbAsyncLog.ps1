function Update-PfbAsyncLog {
    <#
    .SYNOPSIS
        Updates an asynchronous log collection job on the FlashBlade.
    .DESCRIPTION
        The Update-PfbAsyncLog cmdlet modifies the asynchronous log collection job on the
        connected Everpure FlashBlade. Supply the changed properties via Attributes or the
        individual parameters.

        PATCH /logs-async takes no query parameters and no selector: the array has one async
        log collection to configure, not a collection of named jobs. The endpoint requires
        start_time on every request, even though the spec marks no field as required.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
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
        Update-PfbAsyncLog -StartTime 1700000000000 -EndTime 1700003600000

        Sets the processing time window using typed parameters.
    .EXAMPLE
        Update-PfbAsyncLog -StartTime 1700000000000 -HardwareComponents 'CH1.FB1','CH1.FB2'

        Restricts log processing to two hardware components over the given window.
    .EXAMPLE
        Update-PfbAsyncLog -Attributes @{ start_time = 1700000000000; end_time = 1700003600000 }

        Equivalent to the first example, using the raw attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'Individual')]
    param(
        [Parameter(ParameterSetName = 'Individual')]
        [long]$EndTime,

        [Parameter(ParameterSetName = 'Individual')]
        [string[]]$HardwareComponents,

        [Parameter(ParameterSetName = 'Individual')]
        [long]$StartTime,

        [Parameter(ParameterSetName = 'Attributes', Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Attributes') {
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

        # PATCH /logs-async takes no query parameters in any spec version and ignores any that
        # are sent (issue #64), so there is no per-job target to name here -- the endpoint
        # operates on the array's async log collection itself.
        if ($PSCmdlet.ShouldProcess('logs-async', 'Update async log job')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'logs-async' -Body $body
        }
    }
}
