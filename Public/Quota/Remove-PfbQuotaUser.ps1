function Remove-PfbQuotaUser {
    <#
    .SYNOPSIS
        Removes a user quota from a Pure Storage FlashBlade file system.
    .DESCRIPTION
        The Remove-PfbQuotaUser cmdlet deletes a user quota entry from the specified file system
        on the FlashBlade. This operation has a high confirm impact and will prompt for confirmation
        by default. Use -Confirm:$false to suppress the prompt.
    .PARAMETER FileSystemName
        The name of the file system containing the user quota to remove.
    .PARAMETER UserName
        The name of the user whose quota should be removed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'jdoe'

        Removes the user quota for 'jdoe' on 'fs-home' after prompting for confirmation.
    .EXAMPLE
        Remove-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'former-employee' -Confirm:$false

        Removes the user quota without prompting for confirmation.
    .EXAMPLE
        Remove-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'contractor01' -Array $FlashBlade

        Removes the user quota using a specific FlashBlade connection object.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string]$FileSystemName,
        [Parameter(Mandatory)] [string]$UserName,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $UserName; 'file_system_names' = $FileSystemName }
    if ($PSCmdlet.ShouldProcess("${FileSystemName}:${UserName}", 'Remove user quota')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'quotas/users' -QueryParams $q
    }
}
