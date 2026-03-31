function Remove-PfbNetworkAccessRule {
    <#
    .SYNOPSIS
        Removes a network access policy rule from the FlashBlade.
    .DESCRIPTION
        Deletes a rule from a network access policy identified by rule name or by
        policy name/ID. This action is irreversible. Use -Confirm:$false to suppress
        the confirmation prompt in automation scenarios.
    .PARAMETER Name
        The name of the network access rule to remove (e.g. 'network-access-01.1').
    .PARAMETER PolicyName
        The name of the network access policy whose rule should be removed.
    .PARAMETER PolicyId
        The ID of the network access policy whose rule should be removed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbNetworkAccessRule -Name "network-access-01.1"

        Removes the network access rule by name.
    .EXAMPLE
        Remove-PfbNetworkAccessRule -Name "network-access-01.1" -Confirm:$false

        Removes the network access rule without confirmation.
    .EXAMPLE
        Remove-PfbNetworkAccessRule -PolicyName "network-access-01" -Name "network-access-01.1"

        Removes a specific rule from the named policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$PolicyName,

        [Parameter()]
        [string]$PolicyId,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{ 'names' = $Name }
        if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
        if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }

        if ($PSCmdlet.ShouldProcess($Name, 'Remove network access rule')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'network-access-policies/rules' -QueryParams $queryParams
        }
    }
}
