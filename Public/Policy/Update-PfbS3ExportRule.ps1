function Update-PfbS3ExportRule {
    <#
    .SYNOPSIS
        Updates an existing S3 export policy rule on the FlashBlade.
    .DESCRIPTION
        Modifies an existing rule in an S3 export policy identified by rule name.
        Use the Attributes parameter to supply the properties to update such as
        client, access, permission, or other export settings.
    .PARAMETER Name
        The name of the S3 export rule to update (e.g. 's3-export-01.1').
    .PARAMETER Attributes
        A hashtable of rule properties to update. Only specified properties are changed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbS3ExportRule -Name "s3-export-01.1" -Attributes @{ client = "10.0.0.0/8" }

        Updates the client pattern of the specified rule.
    .EXAMPLE
        Update-PfbS3ExportRule -Name "s3-export-01.1" -Attributes @{ access = "no-root-squash"; permission = "rw" }

        Updates the access and permission settings of the specified rule.
    .EXAMPLE
        Update-PfbS3ExportRule -Name "s3-export-01.1" -Attributes @{ permission = "ro" }

        Changes the rule to read-only.
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

        if ($PSCmdlet.ShouldProcess($Name, 'Update S3 export rule')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 's3-export-policies/rules' -Body $Attributes -QueryParams $queryParams
        }
    }
}
