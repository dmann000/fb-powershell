function Update-PfbAlert {
    <#
    .SYNOPSIS
        Updates an alert on the FlashBlade (e.g., flag/unflag).
    .PARAMETER Name
        The alert name.
    .PARAMETER Id
        The alert ID.
    .PARAMETER Flagged
        Set flagged state.
    .PARAMETER Attributes
        A hashtable of attributes to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbAlert -Id "alert123" -Flagged $true
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [Nullable[bool]]$Flagged,

        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) { $body = $Attributes }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Flagged')) { $body['flagged'] = [bool]$Flagged }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update alert')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'alerts' -Body $body -QueryParams $queryParams
        }
    }
}
