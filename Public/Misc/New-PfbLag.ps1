function New-PfbLag {
    <#
    .SYNOPSIS
        Creates a new link aggregation group (LAG) on the FlashBlade.
    .DESCRIPTION
        Creates a new LAG to bond multiple physical network ports together for increased
        bandwidth and redundancy on the FlashBlade array.
    .PARAMETER Name
        The name of the LAG to create.
    .PARAMETER Attributes
        A hashtable of additional LAG attributes such as ports and LACP configuration.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbLag -Name "lag1"

        Creates a new LAG named 'lag1' with default settings.
    .EXAMPLE
        New-PfbLag -Name "lag1" -Attributes @{ ports = @(@{ name = "CH1.FM1.ETH1" }, @{ name = "CH1.FM1.ETH2" }) }

        Creates a new LAG named 'lag1' with the specified ports.
    .EXAMPLE
        New-PfbLag -Name "lag2" -Attributes @{ lacp_mode = "active" }

        Creates a new LAG named 'lag2' with active LACP mode.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    $body = if ($Attributes) { $Attributes } else { @{} }
    if ($PSCmdlet.ShouldProcess($Name, 'Create LAG')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'link-aggregation-groups' -Body $body -QueryParams $q
    }
}
