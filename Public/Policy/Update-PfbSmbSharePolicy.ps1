function Update-PfbSmbSharePolicy {
    <#
    .SYNOPSIS
        Updates an existing SMB share policy on the FlashBlade.
    .DESCRIPTION
        Modifies an existing SMB share policy identified by name or ID.
        Supports enabling or disabling the policy and updating attributes.
        The Enabled parameter accepts $true or $false and can be used with
        the colon syntax (e.g. -Enabled:$false).
    .PARAMETER Name
        The name of the SMB share policy to update.
    .PARAMETER Id
        The ID of the SMB share policy to update.
    .PARAMETER Enabled
        Enable or disable the SMB share policy. Use -Enabled:$true or -Enabled:$false.
    .PARAMETER Attributes
        A hashtable of attributes to update. When specified, this is used as the
        entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSmbSharePolicy -Name "smb-share-01" -Enabled:$false

        Disables the SMB share policy named 'smb-share-01'.
    .EXAMPLE
        Update-PfbSmbSharePolicy -Id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Enabled:$true

        Enables the SMB share policy by ID.
    .EXAMPLE
        Update-PfbSmbSharePolicy -Name "smb-share-01" -Attributes @{ rules = @(@{ principal = "Administrators"; full_control = "allow" }) }

        Updates the SMB share policy rules using an attributes hashtable.
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

        if ($PSCmdlet.ShouldProcess($target, 'Update SMB share policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'smb-share-policies' -Body $body -QueryParams $queryParams
        }
    }
}
