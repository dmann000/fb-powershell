function Remove-PfbLocalGroup {
    <#
    .SYNOPSIS
        Deletes a local group from the FlashBlade.
    .DESCRIPTION
        Deletes one or more local groups. Endpoint: DELETE /directory-services/local/groups.
    .PARAMETER Name
        One or more local group names to delete. Accepts pipeline input.
    .PARAMETER Id
        One or more local group IDs to delete.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbLocalGroup -Name "mydomain\share-admins"

        Deletes the specified local group.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string[]]$Id,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id)   { foreach ($i in $Id)   { $allIds.Add($i) } }
    }
    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']   = $allIds -join ',' }
        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }

        $target = if ($allNames.Count -gt 0) { $allNames -join ',' } else { $allIds -join ',' }
        if ($PSCmdlet.ShouldProcess($target, 'Delete local group')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'directory-services/local/groups' -QueryParams $queryParams
        }
    }
}
