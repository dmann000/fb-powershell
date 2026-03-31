function Update-PfbSmbClientRule {
    <#
    .SYNOPSIS
        Updates an existing SMB client policy rule on the FlashBlade.
    .DESCRIPTION
        Modifies an existing rule in an SMB client policy identified by rule name.
        Use the Attributes parameter to supply the properties to update such as
        client pattern or encryption settings.
    .PARAMETER Name
        The name of the SMB client rule to update (e.g. 'smb-client-01.1').
    .PARAMETER Attributes
        A hashtable of rule properties to update. Only specified properties are changed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSmbClientRule -Name "smb-client-01.1" -Attributes @{ client = "10.0.0.0/8" }

        Updates the client pattern of the specified rule.
    .EXAMPLE
        Update-PfbSmbClientRule -Name "smb-client-01.1" -Attributes @{ encryption = "required" }

        Updates the encryption setting of the specified rule.
    .EXAMPLE
        Update-PfbSmbClientRule -Name "smb-client-01.1" -Attributes @{ client = "192.168.1.0/24"; encryption = "optional" }

        Updates multiple properties of the specified rule.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{ 'names' = $Name }

        if ($PSCmdlet.ShouldProcess($Name, 'Update SMB client rule')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'smb-client-policies/rules' -Body $Attributes -QueryParams $queryParams
        }
    }
}
