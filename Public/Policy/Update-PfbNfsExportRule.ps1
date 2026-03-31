function Update-PfbNfsExportRule {
    <#
    .SYNOPSIS
        Updates an existing NFS export policy rule on the FlashBlade.
    .DESCRIPTION
        Modifies an existing rule in an NFS export policy identified by rule name.
        Use the Attributes parameter to supply the properties to update such as
        client, access, permission, or security settings.
    .PARAMETER Name
        The name of the NFS export rule to update (e.g. 'nfs-export-01.1').
    .PARAMETER Attributes
        A hashtable of rule properties to update. Only specified properties are changed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbNfsExportRule -Name "nfs-export-01.1" -Attributes @{ client = "10.0.0.0/8" }

        Updates the client pattern of the specified rule.
    .EXAMPLE
        Update-PfbNfsExportRule -Name "nfs-export-01.1" -Attributes @{ access = "no-root-squash"; permission = "rw" }

        Updates the access and permission settings of the specified rule.
    .EXAMPLE
        Update-PfbNfsExportRule -Name "nfs-export-01.1" -Attributes @{ security = @("krb5") }

        Updates the security setting of the specified rule to Kerberos 5.
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

        if ($PSCmdlet.ShouldProcess($Name, 'Update NFS export rule')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'nfs-export-policies/rules' -Body $Attributes -QueryParams $queryParams
        }
    }
}
