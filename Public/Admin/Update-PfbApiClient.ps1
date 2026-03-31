function Update-PfbApiClient {
    <#
    .SYNOPSIS
        Updates an API client on the FlashBlade.
    .DESCRIPTION
        The Update-PfbApiClient cmdlet modifies an existing API client on the connected
        Pure Storage FlashBlade. Properties that can be updated include the public key,
        maximum role, and enabled state.
    .PARAMETER Name
        The name of the API client to update.
    .PARAMETER Id
        The ID of the API client to update.
    .PARAMETER Attributes
        A hashtable of properties to update on the API client.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbApiClient -Name 'automation-client' -Attributes @{ enabled = $true }

        Enables the API client named 'automation-client'.
    .EXAMPLE
        Update-PfbApiClient -Name 'automation-client' -Attributes @{ max_role = @{ name = 'readonly' } }

        Changes the maximum role of the API client to read-only.
    .EXAMPLE
        Update-PfbApiClient -Id '12345678-abcd-efgh-ijkl-123456789012' -Attributes @{ public_key = $newKey }

        Updates the public key of an API client by ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update API client')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'api-clients' -Body $Attributes -QueryParams $queryParams
        }
    }
}
