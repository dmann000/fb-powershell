function New-PfbQosPolicy {
    <#
    .SYNOPSIS
        Creates a new QoS policy on a FlashBlade array.
    .DESCRIPTION
        The New-PfbQosPolicy cmdlet creates a new Quality of Service policy on the connected
        Pure Storage FlashBlade. QoS policies define bandwidth and IOPS limits.
    .PARAMETER Name
        The name for the new QoS policy.
    .PARAMETER Attributes
        A hashtable of QoS policy attributes. Valid keys include:
        max_total_bytes_per_sec (1MB/s to 512GB/s), max_total_ops_per_sec (100 to 100M),
        min_total_bytes_per_sec, min_total_ops_per_sec.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbQosPolicy -Name "qos-gold" -Attributes @{ max_total_bytes_per_sec = 1073741824 }

        Creates a QoS policy with a 1 GB/s maximum bandwidth limit.
    .EXAMPLE
        New-PfbQosPolicy -Name "qos-silver" -Attributes @{ max_total_ops_per_sec = 10000 }

        Creates a QoS policy with a 10000 IOPS maximum limit.
    .EXAMPLE
        New-PfbQosPolicy -Name "qos-test" -Attributes @{} -WhatIf

        Shows what would happen without actually creating the policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter()] [hashtable]$Attributes = @{},
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create QoS policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'qos-policies' -Body $Attributes -QueryParams $queryParams
    }
}
