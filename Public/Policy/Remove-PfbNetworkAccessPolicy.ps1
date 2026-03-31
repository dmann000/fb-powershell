function Remove-PfbNetworkAccessPolicy {
    <#
    .SYNOPSIS
        Removes a network access policy from the FlashBlade.
    .DESCRIPTION
        Deletes a network access policy identified by name or ID from the FlashBlade.
        This action is irreversible. Use -Confirm:$false to suppress the confirmation
        prompt in automation scenarios.
    .PARAMETER Name
        The name of the network access policy to remove.
    .PARAMETER Id
        The ID of the network access policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbNetworkAccessPolicy -Name "net-access-01"

        Removes the network access policy named 'net-access-01'.
    .EXAMPLE
        Remove-PfbNetworkAccessPolicy -Id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

        Removes the network access policy by ID.
    .EXAMPLE
        Remove-PfbNetworkAccessPolicy -Name "net-access-01" -Confirm:$false

        Removes the network access policy without confirmation.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove network access policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'network-access-policies' -QueryParams $queryParams
        }
    }
}
