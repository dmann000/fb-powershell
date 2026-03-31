function Update-PfbPolicy {
    <#
    .SYNOPSIS
        Updates an existing policy on the FlashBlade.
    .PARAMETER Name
        The name of the policy to update.
    .PARAMETER Id
        The ID of the policy to update.
    .PARAMETER Enabled
        Enable or disable the policy.
    .PARAMETER Rules
        Updated array of policy rule hashtables.
    .PARAMETER Attributes
        A hashtable of attributes to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbPolicy -Name "daily-snap" -Enabled:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [Nullable[bool]]$Enabled,

        [Parameter()]
        [hashtable[]]$Rules,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) { $body = $Attributes }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
            if ($Rules)             { $body['rules'] = $Rules }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'policies' -Body $body -QueryParams $queryParams
        }
    }
}
