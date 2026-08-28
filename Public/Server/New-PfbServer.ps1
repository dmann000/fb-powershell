function New-PfbServer {
    <#
    .SYNOPSIS
        Creates a new server on the FlashBlade.
    .DESCRIPTION
        Creates a server, optionally attaching a DNS config and a local directory service.
        The FlashBlade also auto-creates a directory service named "{Name}_nfs" for the
        new server (controlled by the `create_ds` query parameter).
    .PARAMETER Name
        Name of the server to create.
    .PARAMETER DnsName
        Name(s) of pre-existing DNS configs to attach. FlashBlade accepts at most one.
    .PARAMETER LocalDirectoryService
        Name of the Local Directory Service to associate with the server.
    .PARAMETER CreateDirectoryService
        Override the auto-created NFS directory service name. Defaults to "{Name}_nfs".
        Pass an empty string to skip auto-creation if the FlashBlade supports it.
    .PARAMETER Attributes
        Full request body as a hashtable. Mutually exclusive with the typed parameters
        above -- use only when a field you need isn't exposed.
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        New-PfbServer -Name "server5"
    .EXAMPLE
        New-PfbServer -Name "server5" -DnsName "management" -LocalDirectoryService "server5_nfs"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Individual')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = 'Individual')]
        [string[]]$DnsName,

        [Parameter(ParameterSetName = 'Individual')]
        [string]$LocalDirectoryService,

        [Parameter()]
        [string]$CreateDirectoryService,

        [Parameter(Mandatory, ParameterSetName = 'Attributes')]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSCmdlet.ParameterSetName -eq 'Attributes') {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($DnsName)               { $body['dns'] = @($DnsName | ForEach-Object { @{ name = $_ } }) }
        if ($LocalDirectoryService) { $body['local_directory_service'] = @{ name = $LocalDirectoryService } }
    }

    $createDs = if ($PSBoundParameters.ContainsKey('CreateDirectoryService')) { $CreateDirectoryService } else { "${Name}_nfs" }

    $queryParams = @{ 'names' = $Name }
    if ($createDs) { $queryParams['create_ds'] = $createDs }

    if ($PSCmdlet.ShouldProcess($Name, 'Create server')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'servers' -Body $body -QueryParams $queryParams
    }
}
