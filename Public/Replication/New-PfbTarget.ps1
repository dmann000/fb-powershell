function New-PfbTarget {
    <#
    .SYNOPSIS
        Creates a new replication target on a FlashBlade array.
    .DESCRIPTION
        The New-PfbTarget cmdlet creates a new replication target on the connected Pure Storage
        FlashBlade. Targets define the remote destination for replication and can include remote
        FlashBlade arrays or S3-compatible object store endpoints. The Attributes hashtable
        specifies the target configuration details. Supports ShouldProcess for confirmation.
    .PARAMETER Name
        The name for the new replication target.
    .PARAMETER Attributes
        A hashtable of target attributes including address, type, and credentials as applicable.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbTarget -Name "s3-target-aws" -Attributes @{ address = "s3.amazonaws.com"; bucket = "fb-replication" }

        Creates a new replication target pointing to an AWS S3 bucket.
    .EXAMPLE
        New-PfbTarget -Name "remote-fb-dc2" -Attributes @{ address = "10.0.2.100"; connection_key = "abc-123" }

        Creates a new replication target for a remote FlashBlade array.
    .EXAMPLE
        New-PfbTarget -Name "s3-archive" -Attributes @{ address = "s3.us-west-2.amazonaws.com"; bucket = "archive-bucket" } -WhatIf

        Shows what would happen if the replication target were created without actually creating it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create target')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'targets' -Body $Attributes -QueryParams $q
    }
}
