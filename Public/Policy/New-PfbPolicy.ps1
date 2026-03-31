function New-PfbPolicy {
    <#
    .SYNOPSIS
        Creates a new snapshot or replication policy on the FlashBlade.
    .PARAMETER Name
        The name of the policy to create.
    .PARAMETER Enabled
        Whether the policy is enabled.
    .PARAMETER Rules
        An array of policy rule hashtables.
    .PARAMETER Attributes
        A hashtable of additional attributes.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbPolicy -Name "daily-snap" -Attributes @{ rules = @(@{ every = 86400000; keep_for = 604800000 }) }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$Enabled,

        [Parameter()]
        [hashtable[]]$Rules,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
        if ($Rules) { $body['rules'] = $Rules }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'policies' -Body $body -QueryParams $queryParams
    }
}
