function New-PfbSmbClientPolicy {
    <#
    .SYNOPSIS
        Creates a new SMB client policy on the FlashBlade.
    .DESCRIPTION
        Creates a new SMB client policy with the specified name and optional settings.
        Use the Attributes parameter to supply a complete body hashtable, or use
        individual parameters to build the request.
    .PARAMETER Name
        The name of the SMB client policy to create.
    .PARAMETER Enabled
        Whether the policy is enabled upon creation.
    .PARAMETER Attributes
        A hashtable of additional attributes for the policy body.
        When specified, this is used as the entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSmbClientPolicy -Name "smb-client-01"

        Creates a new SMB client policy named 'smb-client-01'.
    .EXAMPLE
        New-PfbSmbClientPolicy -Name "smb-client-01" -Enabled

        Creates a new enabled SMB client policy.
    .EXAMPLE
        New-PfbSmbClientPolicy -Name "smb-client-01" -Attributes @{ enabled = $true; rules = @(@{ client = "*" }) }

        Creates a new SMB client policy with custom attributes.
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

    if ($PSCmdlet.ShouldProcess($Name, 'Create SMB client policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'smb-client-policies' -Body $body -QueryParams $queryParams
    }
}
