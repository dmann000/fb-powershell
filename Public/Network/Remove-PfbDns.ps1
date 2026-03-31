function Remove-PfbDns {
    <#
    .SYNOPSIS
        Removes a DNS configuration entry from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbDns cmdlet deletes a DNS configuration entry from the connected Pure
        Storage FlashBlade. The entry can be identified by name or ID.
    .PARAMETER Name
        The name of the DNS entry to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the DNS entry to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbDns -Name "dns-old"

        Removes the DNS entry after prompting for confirmation.
    .EXAMPLE
        Remove-PfbDns -Name "dns-test" -Confirm:$false

        Removes the DNS entry without prompting.
    .EXAMPLE
        Remove-PfbDns -Id "10314f42-020d-7080-8013-000ddt400012"

        Removes the DNS entry by ID after prompting.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove DNS configuration')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'dns' -QueryParams $queryParams
        }
    }
}
