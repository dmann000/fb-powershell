function New-PfbObjectStoreAccountExport {
    <#
    .SYNOPSIS
        Creates a new object store account export on the FlashBlade.
    .DESCRIPTION
        Creates an account export configuration that controls how an object
        store account is exposed through NFS or other export protocols.
    .PARAMETER Name
        The name of the account export to create.
    .PARAMETER Attributes
        A hashtable of export properties such as account, enabled, or
        export rules.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccountExport -Name "nfs-export-1" -Attributes @{
            account = @{ name = "myaccount" }
        }
        Creates an account export linked to the specified account.
    .EXAMPLE
        New-PfbObjectStoreAccountExport -Name "export-acct-prod" -Attributes @{
            account = @{ name = "prod-account" }
            enabled = $true
        }
        Creates and enables an account export.
    .EXAMPLE
        New-PfbObjectStoreAccountExport -Name "basic-export"
        Creates an account export with default settings.
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

    if ($PSCmdlet.ShouldProcess($Name, 'Create object store account export')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-account-exports' -Body $body -QueryParams $queryParams
    }
}
