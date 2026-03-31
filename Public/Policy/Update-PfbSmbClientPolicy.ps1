function Update-PfbSmbClientPolicy {
    <#
    .SYNOPSIS
        Updates an existing SMB client policy on the FlashBlade.
    .DESCRIPTION
        Modifies an existing SMB client policy identified by name or ID.
        Supports enabling or disabling the policy and updating attributes.
        The Enabled parameter accepts $true or $false and can be used with
        the colon syntax (e.g. -Enabled:$false).
    .PARAMETER Name
        The name of the SMB client policy to update.
    .PARAMETER Id
        The ID of the SMB client policy to update.
    .PARAMETER Enabled
        Enable or disable the SMB client policy. Use -Enabled:$true or -Enabled:$false.
    .PARAMETER Attributes
        A hashtable of attributes to update. When specified, this is used as the
        entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSmbClientPolicy -Name "smb-client-01" -Enabled:$false

        Disables the SMB client policy named 'smb-client-01'.
    .EXAMPLE
        Update-PfbSmbClientPolicy -Id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Enabled:$true

        Enables the SMB client policy by ID.
    .EXAMPLE
        Update-PfbSmbClientPolicy -Name "smb-client-01" -Attributes @{ rules = @(@{ client = "10.0.0.0/8" }) }

        Updates the SMB client policy rules using an attributes hashtable.
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

        if ($PSCmdlet.ShouldProcess($target, 'Update SMB client policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'smb-client-policies' -Body $body -QueryParams $queryParams
        }
    }
}
