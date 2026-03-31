function New-PfbObjectStoreRemoteCredential {
    <#
    .SYNOPSIS
        Creates a new object store remote credential on the FlashBlade.
    .DESCRIPTION
        Creates a remote credential for authenticating to an external S3-compatible
        object store for replication purposes. Requires an access key ID and secret.
    .PARAMETER Name
        The name of the remote credential to create.
    .PARAMETER Attributes
        A hashtable of credential properties including access_key_id, secret_access_key,
        and the remote array or target information.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreRemoteCredential -Name "s3-repl-cred" -Attributes @{
            access_key_id = "AKIAIOSFODNN7EXAMPLE"
            secret_access_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        }
        Creates a remote credential with the specified access keys.
    .EXAMPLE
        New-PfbObjectStoreRemoteCredential -Name "backup-target" -Attributes @{
            access_key_id = "AKIAI44QH8DHBEXAMPLE"
            secret_access_key = "je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY"
        }
        Creates a remote credential for a backup target.
    .EXAMPLE
        New-PfbObjectStoreRemoteCredential -Name "dr-cred"
        Creates a remote credential with no additional attributes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create object store remote credential')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-remote-credentials' -Body $body -QueryParams $queryParams
    }
}
