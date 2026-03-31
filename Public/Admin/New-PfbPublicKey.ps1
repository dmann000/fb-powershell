function New-PfbPublicKey {
    <#
    .SYNOPSIS
        Uploads a public key to the FlashBlade.
    .DESCRIPTION
        The New-PfbPublicKey cmdlet uploads a new public key to the connected Pure Storage
        FlashBlade. Public keys are used for SSH authentication and can be associated with
        administrator accounts for key-based login.
    .PARAMETER Name
        The name to assign to the public key.
    .PARAMETER Attributes
        A hashtable defining the public key properties, including the key data.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbPublicKey -Name 'admin-ssh-key' -Attributes @{ public_key = $sshKey }

        Uploads a new public key named 'admin-ssh-key' with the specified key data.
    .EXAMPLE
        $key = Get-Content ~/.ssh/id_rsa.pub -Raw
        New-PfbPublicKey -Name 'ops-key' -Attributes @{ public_key = $key }

        Reads a public key from a file and uploads it to the FlashBlade.
    .EXAMPLE
        New-PfbPublicKey -Name 'deploy-key' -Attributes @{ public_key = $key } -Confirm:$false

        Uploads a public key without prompting for confirmation.
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

    if ($PSCmdlet.ShouldProcess($Name, 'Upload public key')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'public-keys' -Body $body -QueryParams $queryParams
    }
}
