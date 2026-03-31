function New-PfbSmbSharePolicy {
    <#
    .SYNOPSIS
        Creates a new SMB share policy on the FlashBlade.
    .DESCRIPTION
        Creates a new SMB share policy with the specified name and optional settings.
        Use the Attributes parameter to supply a complete body hashtable, or use
        individual parameters to build the request.
    .PARAMETER Name
        The name of the SMB share policy to create.
    .PARAMETER Enabled
        Whether the policy is enabled upon creation.
    .PARAMETER Attributes
        A hashtable of additional attributes for the policy body.
        When specified, this is used as the entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSmbSharePolicy -Name "smb-share-01"

        Creates a new SMB share policy named 'smb-share-01'.
    .EXAMPLE
        New-PfbSmbSharePolicy -Name "smb-share-01" -Enabled

        Creates a new enabled SMB share policy.
    .EXAMPLE
        New-PfbSmbSharePolicy -Name "smb-share-01" -Attributes @{ enabled = $true; rules = @(@{ principal = "Everyone"; change = "allow" }) }

        Creates a new SMB share policy with custom attributes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$Enabled,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create SMB share policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'smb-share-policies' -Body $body -QueryParams $queryParams
    }
}
