function New-PfbApiClient {
    <#
    .SYNOPSIS
        Creates a new API client on the FlashBlade.
    .DESCRIPTION
        The New-PfbApiClient cmdlet creates a new API client on the connected Pure Storage
        FlashBlade. API clients are used for OAuth2 authentication and require at minimum
        a public key and a maximum role assignment.
    .PARAMETER Name
        The name of the API client to create.
    .PARAMETER Attributes
        A hashtable defining the API client properties, including the public key and role.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbApiClient -Name 'automation-client' -Attributes @{ max_role = @{ name = 'storage_admin' }; public_key = $key }

        Creates a new API client with the storage_admin role and the specified public key.
    .EXAMPLE
        New-PfbApiClient -Name 'readonly-client' -Attributes @{ max_role = @{ name = 'readonly' }; public_key = $key }

        Creates a new read-only API client.
    .EXAMPLE
        New-PfbApiClient -Name 'ops-client' -Attributes @{ max_role = @{ name = 'ops_admin' }; public_key = $key } -Confirm:$false

        Creates a new API client without prompting for confirmation.
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

    if ($PSCmdlet.ShouldProcess($Name, 'Create API client')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'api-clients' -Body $body -QueryParams $queryParams
    }
}
