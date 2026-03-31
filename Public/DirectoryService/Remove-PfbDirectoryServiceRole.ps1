function Remove-PfbDirectoryServiceRole {
    <#
    .SYNOPSIS
        Removes a directory service role from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbDirectoryServiceRole cmdlet deletes a directory service role from the
        connected Pure Storage FlashBlade. The target role can be identified by name or ID.
        This is a destructive operation and requires confirmation by default.
    .PARAMETER Name
        The name of the directory service role to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the directory service role to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbDirectoryServiceRole -Name "ad-admins"

        Removes the directory service role named "ad-admins".
    .EXAMPLE
        Remove-PfbDirectoryServiceRole -Id "abc12345-6789-0abc-def0-123456789abc" -Confirm:$false

        Removes the directory service role without confirmation.
    .EXAMPLE
        "test-role" | Remove-PfbDirectoryServiceRole

        Removes the directory service role via pipeline input.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

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

        if ($PSCmdlet.ShouldProcess($target, 'Remove directory service role')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'directory-services/roles' -QueryParams $queryParams
        }
    }
}
