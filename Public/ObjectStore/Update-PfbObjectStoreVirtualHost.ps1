function Update-PfbObjectStoreVirtualHost {
    <#
    .SYNOPSIS
        Updates an existing object store virtual host on the FlashBlade.
    .DESCRIPTION
        Modifies the properties of an existing object store virtual host,
        such as its enabled state or associated access policies.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the virtual host to update.
    .PARAMETER Id
        The ID of the virtual host to update.
    .PARAMETER AddAttachedServers
        A list of new servers which are allowed to use this virtual host.
    .PARAMETER AttachedServers
        A list of servers which are allowed to use this virtual host.
    .PARAMETER Hostname
        A hostname by which the array can be addressed for virtual hosted-style S3 requests.
    .PARAMETER NewName
        A new user-specified name for the virtual host.
    .PARAMETER RemoveAttachedServers
        A list of servers which will no longer be allowed to use this virtual host.
    .PARAMETER Attributes
        A hashtable of virtual host properties to update. Mutually exclusive with
        the individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbObjectStoreVirtualHost -Name "s3.example.com" -Hostname "s3.myarray.com"

        Sets the hostname for the specified virtual host using a typed parameter.
    .EXAMPLE
        Update-PfbObjectStoreVirtualHost -Name "s3.example.com" -Attributes @{
            enabled = $true
        }
        Enables the specified virtual host.
    .EXAMPLE
        Update-PfbObjectStoreVirtualHost -Id "10314f42-020d-7080-8013-000ddt400090" -Attributes @{
            enabled = $false
        }
        Disables a virtual host by its ID.
    .EXAMPLE
        Update-PfbObjectStoreVirtualHost -Name "data.example.com" -Attributes @{}
        Sends an empty update to refresh the virtual host object.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$AddAttachedServers,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$AttachedServers,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Hostname,

        # EXCEPTION: the wire field is literally `name` (a rename), so the parameter is
        # -NewName, never -VirtualHostName -- see Global Constraint on the `name` field.
        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string[]]$RemoveAttachedServers,

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

            # Constraint 8(b): add_attached_servers/attached_servers/remove_attached_servers
            # are ARRAYS OF REFERENCES (item schema is {id, name, resource_type}), so the
            # parameters are [string[]] and each projection is assigned INLINE -- constraint 7
            # forbids an intermediate local variable here.
            if ($PSBoundParameters.ContainsKey('AddAttachedServers')) {
                $body['add_attached_servers'] = @($AddAttachedServers | ForEach-Object { @{ name = $_ } })
            }
            if ($PSBoundParameters.ContainsKey('AttachedServers')) {
                $body['attached_servers'] = @($AttachedServers | ForEach-Object { @{ name = $_ } })
            }
            if ($PSBoundParameters.ContainsKey('Hostname')) { $body['hostname'] = $Hostname }
            if ($PSBoundParameters.ContainsKey('NewName'))  { $body['name']     = $NewName }
            if ($PSBoundParameters.ContainsKey('RemoveAttachedServers')) {
                $body['remove_attached_servers'] = @($RemoveAttachedServers | ForEach-Object { @{ name = $_ } })
            }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update object store virtual host')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'object-store-virtual-hosts' -Body $body -QueryParams $queryParams
        }
    }
}
