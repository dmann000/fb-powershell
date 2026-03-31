function Update-PfbAdminSetting {
    <#
    .SYNOPSIS
        Updates admin settings on the FlashBlade.
    .DESCRIPTION
        The Update-PfbAdminSetting cmdlet modifies global administrator settings on the connected
        Pure Storage FlashBlade. Settings that can be modified include lockout policy, single
        sign-on configuration, and other administrative-level options.
    .PARAMETER Attributes
        A hashtable of settings to update. Keys correspond to FlashBlade admin setting properties.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbAdminSetting -Attributes @{ lockout_duration = 900000 }

        Sets the account lockout duration to 15 minutes (900000 milliseconds).
    .EXAMPLE
        Update-PfbAdminSetting -Attributes @{ max_login_attempts = 5 }

        Sets the maximum number of login attempts before lockout to 5.
    .EXAMPLE
        Update-PfbAdminSetting -Attributes @{ single_sign_on_enabled = $true } -Confirm:$false

        Enables single sign-on without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSCmdlet.ShouldProcess('Admin Settings', 'Update admin settings')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'admins/settings' -Body $Attributes
    }
}
