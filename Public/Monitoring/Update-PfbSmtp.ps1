function Update-PfbSmtp {
    <#
    .SYNOPSIS
        Updates the SMTP configuration on a Pure Storage FlashBlade.
    .DESCRIPTION
        The Update-PfbSmtp cmdlet modifies the SMTP relay and sender domain settings used by the
        FlashBlade for sending email alerts and notifications. Individual properties can be set
        via dedicated parameters, or a complete configuration can be provided through the Attributes
        hashtable. This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER RelayHost
        The hostname or IP address of the SMTP relay server.
    .PARAMETER SenderDomain
        The domain name used in the sender address for outgoing email notifications.
    .PARAMETER Attributes
        A hashtable containing SMTP configuration attributes. When specified, the RelayHost and
        SenderDomain parameters are ignored.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSmtp -RelayHost 'smtp.example.com' -SenderDomain 'example.com'

        Configures the FlashBlade to use 'smtp.example.com' as the SMTP relay with 'example.com' as the sender domain.
    .EXAMPLE
        Update-PfbSmtp -RelayHost 'mail.corp.local'

        Updates only the SMTP relay host without changing the sender domain.
    .EXAMPLE
        Update-PfbSmtp -Attributes @{ relay_host = 'smtp.example.com'; sender_domain = 'alerts.example.com' }

        Updates the SMTP configuration using a custom attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()] [string]$RelayHost,
        [Parameter()] [string]$SenderDomain,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($RelayHost)    { $body['relay_host'] = $RelayHost }
        if ($SenderDomain) { $body['sender_domain'] = $SenderDomain }
    }
    if ($PSCmdlet.ShouldProcess('SMTP', 'Update SMTP configuration')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'smtp' -Body $body
    }
}
