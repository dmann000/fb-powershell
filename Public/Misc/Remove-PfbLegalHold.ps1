function Remove-PfbLegalHold {
    <#
    .SYNOPSIS
        Removes a legal hold from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbLegalHold cmdlet deletes a legal hold from the connected Pure Storage
        FlashBlade. The hold is identified by name or ID. This is a destructive operation
        and requires confirmation.
    .PARAMETER Name
        The name of the legal hold to remove.
    .PARAMETER Id
        The ID of the legal hold to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbLegalHold -Name "litigation-hold-2024"

        Removes the legal hold named "litigation-hold-2024" after confirmation.
    .EXAMPLE
        Remove-PfbLegalHold -Id "12345" -Confirm:$false

        Removes the legal hold by ID without prompting for confirmation.
    .EXAMPLE
        Get-PfbLegalHold -Name "litigation-hold-2024" | Remove-PfbLegalHold

        Retrieves and removes the specified legal hold via pipeline.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove legal hold')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'legal-holds' -QueryParams $queryParams
        }
    }
}
