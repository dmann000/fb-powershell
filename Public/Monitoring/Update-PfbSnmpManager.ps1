function Update-PfbSnmpManager {
    <#
    .SYNOPSIS
        Updates an existing SNMP manager (trap host) on a Pure Storage FlashBlade.
    .DESCRIPTION
        The Update-PfbSnmpManager cmdlet modifies an existing SNMP manager entry on the connected
        Everpure FlashBlade. The manager can be identified by name or by ID. This cmdlet supports
        pipeline input by property name and the ShouldProcess pattern.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the SNMP manager to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the SNMP manager to update.
    .PARAMETER SnmpHost
        DNS hostname or IP address of a computer that hosts an SNMP manager to which Purity is
        to send trap messages when it generates alerts. Named -SnmpHost rather than -Host
        because -Host is a PowerShell common parameter.
    .PARAMETER NewName
        A new user-specified name for the SNMP manager. Named -NewName rather than -Name
        because -Name already identifies which SNMP manager to update.
    .PARAMETER Notification
        The type of notification the agent will send.
    .PARAMETER V2c
        The v2c configuration of SNMP, as a hashtable -- for example @{ community = 'public' }.
    .PARAMETER V3
        The v3 configuration of SNMP, as a hashtable -- for example @{ auth_protocol = 'SHA' }.
    .PARAMETER Version
        Version of the SNMP protocol to be used by Purity in communications with the specified
        manager.
    .PARAMETER Attributes
        A hashtable containing the SNMP manager attributes to update. Mutually exclusive with
        the individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSnmpManager -Name 'snmp-mgr01' -SnmpHost '10.21.100.55'

        Updates the host address for the SNMP manager named 'snmp-mgr01' using a typed parameter.
    .EXAMPLE
        Update-PfbSnmpManager -Name 'snmp-mgr01' -V2c @{ community = 'new-community' }

        Changes the community string for the specified SNMP manager using a typed parameter.
    .EXAMPLE
        Get-PfbSnmpManager -Name 'snmp-mgr01' | Update-PfbSnmpManager -Attributes @{ version = 'v2c'; community = 'updated' }

        Pipes an SNMP manager object to update its version and community string.
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
        [string]$SnmpHost,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [ValidateSet('inform', 'trap')]
        [string]$Notification,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable]$V2c,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [hashtable]$V3,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [ValidateSet('v2c', 'v3')]
        [string]$Version,

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
            # Every value-carrying parameter is guarded by ContainsKey, never by truthiness --
            # see the canonical explanation in Update-PfbAdmin.ps1.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('SnmpHost'))     { $body['host']         = $SnmpHost }
            if ($PSBoundParameters.ContainsKey('NewName'))      { $body['name']         = $NewName }
            if ($PSBoundParameters.ContainsKey('Notification')) { $body['notification'] = $Notification }
            if ($PSBoundParameters.ContainsKey('Version'))      { $body['version']      = $Version }

            # Constraint 8(c): v2c and v3 are COMPOSITE sub-objects (_snmp_v2c, _snmp_v3_post),
            # not references -- neither has a `name` property, so projecting them into
            # @{ name = ... } would write a field the schema does not have. Pass them straight
            # through.
            if ($PSBoundParameters.ContainsKey('V2c')) { $body['v2c'] = $V2c }
            if ($PSBoundParameters.ContainsKey('V3'))  { $body['v3']  = $V3 }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update SNMP manager')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'snmp-managers' -Body $body -QueryParams $queryParams
        }
    }
}
