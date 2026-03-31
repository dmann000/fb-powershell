function Update-PfbSmbShareRule {
    <#
    .SYNOPSIS
        Updates an existing SMB share policy rule on the FlashBlade.
    .DESCRIPTION
        Modifies an existing rule in an SMB share policy identified by rule name.
        Use the Attributes parameter to supply the properties to update such as
        principal, change, read, or full_control settings.
    .PARAMETER Name
        The name of the SMB share rule to update (e.g. 'smb-share-01.1').
    .PARAMETER Attributes
        A hashtable of rule properties to update. Only specified properties are changed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSmbShareRule -Name "smb-share-01.1" -Attributes @{ principal = "DOMAIN\\Users" }

        Updates the principal of the specified rule.
    .EXAMPLE
        Update-PfbSmbShareRule -Name "smb-share-01.1" -Attributes @{ change = "deny" }

        Denies change access on the specified rule.
    .EXAMPLE
        Update-PfbSmbShareRule -Name "smb-share-01.1" -Attributes @{ full_control = "allow"; read = "allow" }

        Updates multiple permission settings of the specified rule.
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

        if ($PSCmdlet.ShouldProcess($Name, 'Update SMB share rule')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'smb-share-policies/rules' -Body $Attributes -QueryParams $queryParams
        }
    }
}
