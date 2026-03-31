function Write-PfbError {
    <#
    .SYNOPSIS
        Creates standardized error records from FlashBlade API error responses.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$ErrorId = 'PfbApiError',

        [Parameter()]
        [System.Management.Automation.ErrorCategory]$Category = [System.Management.Automation.ErrorCategory]::InvalidOperation,

        [Parameter()]
        [object]$TargetObject,

        [Parameter()]
        [System.Exception]$Exception
    )

    if (-not $Exception) {
        $Exception = [System.Exception]::new($Message)
    }

    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $Exception,
        $ErrorId,
        $Category,
        $TargetObject
    )

    $PSCmdlet.ThrowTerminatingError($errorRecord)
}
