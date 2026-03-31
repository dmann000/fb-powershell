function Remove-PfbApiToken {
    <#
    .SYNOPSIS
        Removes an API token from a FlashBlade administrator account.
    .DESCRIPTION
        The Remove-PfbApiToken cmdlet deletes the API token for a specified administrator account
        on the connected Pure Storage FlashBlade. The administrator can be identified by name or
        ID. This is a destructive operation and requires confirmation by default.
    .PARAMETER Name
        The name of the administrator account whose API token to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the administrator account whose API token to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbApiToken -Name "pureuser"

        Removes the API token for the administrator named "pureuser".
    .EXAMPLE
        Remove-PfbApiToken -Id "10314f42-020d-7080-8013-000ddt400012" -Confirm:$false

        Removes the API token for the specified administrator without confirmation.
    .EXAMPLE
        "ops-admin" | Remove-PfbApiToken

        Removes the API token for the administrator named "ops-admin" via pipeline input.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

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

        if ($PSCmdlet.ShouldProcess($target, 'Remove API token')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'admins/api-tokens' -QueryParams $queryParams
        }
    }
}
