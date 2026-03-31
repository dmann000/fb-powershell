function Update-PfbAsyncLog {
    <#
    .SYNOPSIS
        Updates an asynchronous log collection job on the FlashBlade.
    .DESCRIPTION
        The Update-PfbAsyncLog cmdlet modifies an asynchronous log collection job on the
        connected Pure Storage FlashBlade. Identify the job by name or ID and supply the
        changed properties via Attributes or individual parameters.
    .PARAMETER Name
        The name of the async log job to update.
    .PARAMETER Id
        The ID of the async log job to update.
    .PARAMETER Attributes
        A hashtable of attributes to update on the async log job.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbAsyncLog -Name "log-job-1" -Attributes @{ status = 'cancelled' }

        Cancels the async log job named "log-job-1".
    .EXAMPLE
        Update-PfbAsyncLog -Id "12345" -Attributes @{ status = 'cancelled' }

        Cancels the async log job identified by ID.
    .EXAMPLE
        Update-PfbAsyncLog -Name "log-job-1" -Attributes @{ keep_until = 1700000000000 }

        Updates the retention time for the specified async log job.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $body = if ($Attributes) { $Attributes } else { @{} }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update async log job')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'logs-async' -Body $body -QueryParams $queryParams
        }
    }
}
