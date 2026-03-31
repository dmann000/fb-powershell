function Update-PfbSupport {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('Support', 'Update support configuration')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'support' -Body $Attributes
    }
}
