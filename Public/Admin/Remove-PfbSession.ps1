function Remove-PfbSession {
    <#
    .SYNOPSIS
        Terminates an active session on the FlashBlade.
    .DESCRIPTION
        The Remove-PfbSession cmdlet terminates an active administrator or API session on the
        connected Pure Storage FlashBlade. This is a high-impact operation because terminating
        a session will immediately disconnect the associated user or application.
    .PARAMETER Name
        The name of the session to terminate.
    .PARAMETER Id
        The ID of the session to terminate.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbSession -Name 'session-001'

        Terminates the session named 'session-001' after confirmation.
    .EXAMPLE
        Remove-PfbSession -Id '12345678-abcd-efgh-ijkl-123456789012' -Confirm:$false

        Terminates a session by ID without prompting for confirmation.
    .EXAMPLE
        Get-PfbSession -Filter "user_interface='CLI'" | Remove-PfbSession

        Terminates all CLI sessions via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Terminate session')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'sessions' -QueryParams $queryParams
        }
    }
}
