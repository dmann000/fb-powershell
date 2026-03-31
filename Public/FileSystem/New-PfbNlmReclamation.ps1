function New-PfbNlmReclamation {
    <#
    .SYNOPSIS
        Initiates an NLM lock reclamation on the FlashBlade.
    .DESCRIPTION
        Triggers Network Lock Manager (NLM) lock reclamation for the specified
        file system. This allows NFS clients to reclaim locks after a server
        restart or failover event.
    .PARAMETER Name
        The name of the file system to initiate NLM reclamation for.
    .PARAMETER Attributes
        A hashtable of additional attributes for the reclamation request.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbNlmReclamation -Name "fs01"
        Initiates NLM lock reclamation for file system 'fs01'.
    .EXAMPLE
        New-PfbNlmReclamation -Name "fs01" -Attributes @{ grace_period = 60 }
        Initiates NLM reclamation with a custom grace period.
    .EXAMPLE
        New-PfbNlmReclamation -Name "fs01" -Confirm:$false
        Initiates NLM reclamation without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Initiate NLM lock reclamation')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-systems/locks/nlm-reclamations' -Body $body -QueryParams $queryParams
    }
}
