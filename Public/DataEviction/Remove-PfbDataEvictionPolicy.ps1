function Remove-PfbDataEvictionPolicy {
    <#
    .SYNOPSIS
        Removes a data eviction policy from the FlashBlade.
    .DESCRIPTION
        Deletes a data eviction policy. The policy must not be attached to any file
        systems -- detach via Remove-PfbDataEvictionPolicyFileSystem first.
    .PARAMETER Name
        Policy name to remove.
    .PARAMETER Id
        Policy ID to remove.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Remove-PfbDataEvictionPolicy -Name 'tier-out-100tb'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter()] [PSCustomObject]$Array
    )

    begin { Assert-PfbConnection -Array ([ref]$Array) }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Remove data eviction policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'data-eviction-policies' -QueryParams $queryParams
        }
    }
}
