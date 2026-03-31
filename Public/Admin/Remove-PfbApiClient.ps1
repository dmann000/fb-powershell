function Remove-PfbApiClient {
    <#
    .SYNOPSIS
        Removes an API client from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbApiClient cmdlet deletes an API client from the connected Pure Storage
        FlashBlade. This is a high-impact operation because removing an API client will
        immediately revoke OAuth2 access for any automation using the client.
    .PARAMETER Name
        The name of the API client to remove.
    .PARAMETER Id
        The ID of the API client to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbApiClient -Name 'automation-client'

        Removes the API client named 'automation-client' after confirmation.
    .EXAMPLE
        Remove-PfbApiClient -Name 'automation-client' -Confirm:$false

        Removes the API client without prompting for confirmation.
    .EXAMPLE
        Get-PfbApiClient -Name 'old-client' | Remove-PfbApiClient

        Removes an API client via pipeline input.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove API client')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'api-clients' -QueryParams $queryParams
        }
    }
}
