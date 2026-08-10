function Update-PfbSmtpServer {
    <#
    .SYNOPSIS
        Updates the SMTP server configuration on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbSmtpServer cmdlet modifies the mail relay settings the connected Everpure
        FlashBlade uses to send email alerts and notifications. It PATCHes the /smtp-servers
        endpoint, which has existed since REST 2.0 and replaces the retired Update-PfbSmtp
        cmdlet's legacy REST 1.12 /smtp path.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an explicitly
        supplied value.

        Every body field is guarded by $PSBoundParameters.ContainsKey, never by truthiness. An
        empty string is a legitimate explicit value here -- the API documents `''` as the way to
        clear encryption_mode -- and truthiness would silently drop it.
    .PARAMETER RelayHost
        The hostname or IP address of the SMTP relay server, optionally followed by ':port'.
    .PARAMETER SenderDomain
        The domain name used in the sender address for outgoing email notifications.
    .PARAMETER EncryptionMode
        The encryption mode used for SMTP communication. Valid values include 'starttls'.
        Pass an empty string to clear the setting and send unencrypted.

        Requires REST 2.15 or later. No explicit version gate is declared here: the capability
        map records encryption_mode at 2.15 and Invoke-PfbApiRequest's Assert-PfbApiCapability
        call throws, naming the field, before anything reaches the wire on an older array.
    .PARAMETER Attributes
        A hashtable of SMTP server attributes to update. Mutually exclusive with the individual
        typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSmtpServer -RelayHost 'smtp.example.com' -SenderDomain 'example.com'

        Configures the array to relay mail through smtp.example.com using example.com as the
        sender domain.
    .EXAMPLE
        Update-PfbSmtpServer -EncryptionMode 'starttls'

        Enables STARTTLS for SMTP communication. Requires REST 2.15 or later.
    .EXAMPLE
        Update-PfbSmtpServer -EncryptionMode ''

        Clears the encryption mode, reverting to unencrypted SMTP.
    .EXAMPLE
        Update-PfbSmtpServer -Attributes @{ relay_host = 'smtp.example.com'; sender_domain = 'alerts.example.com' }

        Updates the SMTP server configuration using the raw -Attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Individual')]
    param(
        # Explicit Position: adding a ParameterSetName to any parameter disables PowerShell's
        # implicit positional binding for the WHOLE function, so the positional convention has
        # to be restated here.
        [Parameter(ParameterSetName = 'Individual', Position = 0)] [string]$RelayHost,
        [Parameter(ParameterSetName = 'Individual', Position = 1)] [string]$SenderDomain,

        # No ValidateSet: the spec says valid values "include" starttls, which is open-ended.
        # A ValidateSet would impose a floor the spec does not set.
        [Parameter(ParameterSetName = 'Individual')] [string]$EncryptionMode,

        [Parameter(ParameterSetName = 'Attributes', Mandatory, Position = 0)] [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSCmdlet.ParameterSetName -eq 'Attributes') {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('RelayHost'))      { $body['relay_host']      = $RelayHost }
        if ($PSBoundParameters.ContainsKey('SenderDomain'))   { $body['sender_domain']   = $SenderDomain }
        if ($PSBoundParameters.ContainsKey('EncryptionMode')) { $body['encryption_mode'] = $EncryptionMode }
    }

    $target = if ($PSBoundParameters.ContainsKey('RelayHost')) { $RelayHost } else { 'SMTP server' }
    if ($PSCmdlet.ShouldProcess($target, 'Update SMTP server configuration')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'smtp-servers' -Body $body
    }
}
