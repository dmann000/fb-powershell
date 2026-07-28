function Update-PfbFileSystemExport {
    <#
    .SYNOPSIS
        Updates an existing file system export on the FlashBlade.
    .DESCRIPTION
        Modifies file system export attributes such as rules, enabled state, and
        other export properties. Identify the export by name or ID.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the file system export to update.
    .PARAMETER Id
        The ID of the file system export to update.
    .PARAMETER ExportName
        The name of the export used by clients to mount the file system.
    .PARAMETER Member
        Name of the file system the policy is applied to.
    .PARAMETER Policy
        Name of the NFS export policy or SMB client policy.
    .PARAMETER Server
        Name of the server the export will be visible on.
    .PARAMETER SharePolicy
        Name of the SMB share policy (only used for SMB).
    .PARAMETER Attributes
        A hashtable of attributes to update on the export. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Update-PfbFileSystemExport -Name "export1" -ExportName "/fs1"

        Renames the export used by clients to mount the file system, using a typed parameter.
    .EXAMPLE
        Update-PfbFileSystemExport -Id "abc-123" -Attributes @{ enabled = $false }
        Disables the specified export by ID.
    .EXAMPLE
        Update-PfbFileSystemExport -Name "export1" -Attributes @{ rules = "10.0.0.0/8(rw,no_root_squash)" }
        Updates the export with network-restricted rules.
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
        [string]$ExportName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Member,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Policy,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Server,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$SharePolicy,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Constraint 8(a): member/policy/server/share_policy are all SCALAR references
            # (item schema is {id, name, resource_type}), so the parameter is [string] and
            # the assignment is INLINE -- constraint 7 forbids a local like $memberRef.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('ExportName'))  { $body['export_name'] = $ExportName }
            if ($PSBoundParameters.ContainsKey('Member'))      { $body['member'] = @{ name = $Member } }
            if ($PSBoundParameters.ContainsKey('Policy'))      { $body['policy'] = @{ name = $Policy } }
            if ($PSBoundParameters.ContainsKey('Server'))      { $body['server'] = @{ name = $Server } }
            if ($PSBoundParameters.ContainsKey('SharePolicy')) { $body['share_policy'] = @{ name = $SharePolicy } }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update file system export')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'file-system-exports' -Body $body -QueryParams $queryParams
        }
    }
}
