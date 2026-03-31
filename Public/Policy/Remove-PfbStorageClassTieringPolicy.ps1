function Remove-PfbStorageClassTieringPolicy {
    <#
    .SYNOPSIS
        Removes a storage class tiering policy from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbStorageClassTieringPolicy cmdlet deletes a storage class tiering policy
        from the connected Pure Storage FlashBlade. This cmdlet has a high confirm impact.
    .PARAMETER Name
        The name of the tiering policy to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the tiering policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbStorageClassTieringPolicy -Name "tier-old"

        Removes the tiering policy after prompting for confirmation.
    .EXAMPLE
        Remove-PfbStorageClassTieringPolicy -Name "tier-test" -Confirm:$false

        Removes the tiering policy without prompting.
    .EXAMPLE
        Get-PfbStorageClassTieringPolicy -Filter "enabled='false'" | Remove-PfbStorageClassTieringPolicy

        Removes all disabled tiering policies via pipeline.
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
        if ($Id) { $queryParams['ids'] = $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Remove storage class tiering policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'storage-class-tiering-policies' -QueryParams $queryParams
        }
    }
}
