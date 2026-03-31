function Update-PfbObjectStoreRemoteCredential {
    <#
    .SYNOPSIS
        Updates an existing object store remote credential on the FlashBlade.
    .DESCRIPTION
        Modifies the properties of an existing remote credential, such as
        rotating the access key or secret key used for replication to an
        external S3-compatible target.
    .PARAMETER Name
        The name of the remote credential to update.
    .PARAMETER Id
        The ID of the remote credential to update.
    .PARAMETER Attributes
        A hashtable of credential properties to update, such as access_key_id
        and secret_access_key.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbObjectStoreRemoteCredential -Name "s3-repl-cred" -Attributes @{
            secret_access_key = "newSecretKeyValue12345EXAMPLEKEY"
        }
        Rotates the secret access key for the specified remote credential.
    .EXAMPLE
        Update-PfbObjectStoreRemoteCredential -Id "10314f42-020d-7080-8013-000ddt400090" -Attributes @{
            access_key_id = "AKIAI44QH8DHBEXAMPLE"
            secret_access_key = "je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY"
        }
        Updates both access key fields by credential ID.
    .EXAMPLE
        Update-PfbObjectStoreRemoteCredential -Name "backup-target" -Attributes @{
            access_key_id = "AKIAIOSFODNN7EXAMPLE"
        }
        Updates the access key ID for the backup-target credential.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $body = if ($Attributes) { $Attributes } else { @{} }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update object store remote credential')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'object-store-remote-credentials' -Body $body -QueryParams $queryParams
        }
    }
}
