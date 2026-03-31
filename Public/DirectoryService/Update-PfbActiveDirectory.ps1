function Update-PfbActiveDirectory {
    <#
    .SYNOPSIS
        Updates an existing Active Directory configuration on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbActiveDirectory cmdlet modifies attributes of an existing Active Directory
        configuration on the connected Pure Storage FlashBlade. The target configuration can be
        identified by name or ID. Common updates include changing directory servers, encryption
        types, and service principal names. Supports pipeline input and ShouldProcess.
    .PARAMETER Name
        The name of the Active Directory configuration to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the Active Directory configuration to update.
    .PARAMETER Attributes
        A hashtable of Active Directory attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbActiveDirectory -Name "ad1" -Attributes @{ directory_servers = @("dc02.corp.example.com") }

        Updates the directory servers for the Active Directory configuration named "ad1".
    .EXAMPLE
        Update-PfbActiveDirectory -Name "ad-prod" -Attributes @{ computer_name = "FLASHBLADE02" }

        Changes the computer account name for the "ad-prod" Active Directory configuration.
    .EXAMPLE
        Update-PfbActiveDirectory -Id "10314f42-020d-7080-8013-000ddt400055" -Attributes @{ encryption_types = @("aes256-cts-hmac-sha1-96") }

        Updates the encryption types for the Active Directory configuration identified by ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }
        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update Active Directory')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'active-directory' -Body $Attributes -QueryParams $queryParams
        }
    }
}
