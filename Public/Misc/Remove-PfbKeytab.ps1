function Remove-PfbKeytab {
    <#
    .SYNOPSIS
        Removes a Kerberos keytab entry from the FlashBlade.
    .DESCRIPTION
        Deletes a Kerberos keytab entry from the FlashBlade array. This operation requires
        confirmation due to its high impact on authentication services.
    .PARAMETER Name
        The name of the keytab entry to remove.
    .PARAMETER Id
        The ID of the keytab entry to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbKeytab -Name "krb-keytab-1"

        Removes the keytab entry named 'krb-keytab-1' after confirmation.
    .EXAMPLE
        Remove-PfbKeytab -Name "krb-keytab-1" -Confirm:$false

        Removes the keytab entry named 'krb-keytab-1' without prompting for confirmation.
    .EXAMPLE
        Get-PfbKeytab | Remove-PfbKeytab

        Removes all keytab entries via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove keytab')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'keytabs' -QueryParams $queryParams
        }
    }
}
