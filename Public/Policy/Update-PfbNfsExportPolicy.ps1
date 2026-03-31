function Update-PfbNfsExportPolicy {
    <#
    .SYNOPSIS
        Updates an existing NFS export policy on the FlashBlade.
    .DESCRIPTION
        Modifies an existing NFS export policy identified by name or ID.
        Supports enabling or disabling the policy and updating attributes.
        The Enabled parameter accepts $true or $false and can be used with
        the colon syntax (e.g. -Enabled:$false).
    .PARAMETER Name
        The name of the NFS export policy to update.
    .PARAMETER Id
        The ID of the NFS export policy to update.
    .PARAMETER Enabled
        Enable or disable the NFS export policy. Use -Enabled:$true or -Enabled:$false.
    .PARAMETER Attributes
        A hashtable of attributes to update. When specified, this is used as the
        entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbNfsExportPolicy -Name "nfs-export-01" -Enabled:$false

        Disables the NFS export policy named 'nfs-export-01'.
    .EXAMPLE
        Update-PfbNfsExportPolicy -Id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Enabled:$true

        Enables the NFS export policy by ID.
    .EXAMPLE
        Update-PfbNfsExportPolicy -Name "nfs-export-01" -Attributes @{ rules = @(@{ client = "10.0.0.0/8"; access = "no-root-squash" }) }

        Updates the NFS export policy rules using an attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [Nullable[bool]]$Enabled,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) { $body = $Attributes }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update NFS export policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'nfs-export-policies' -Body $body -QueryParams $queryParams
        }
    }
}
