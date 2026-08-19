function Test-PfbEmptyPipelineRead {
    <#
    .SYNOPSIS
        Detects an empty pipeline invocation that would issue an unfiltered request.
    .DESCRIPTION
        Public collect-in-process cmdlets call this from end after building their final
        query hashtable. A piped invocation with no final query key received no object to
        select; issuing the request would turn that absence into an unfiltered read/write.
        Direct calls are not suppressed, and any surviving query key leaves the request alone.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Caller,

        [AllowNull()]
        [System.Collections.IDictionary]$QueryParams
    )

    if (-not $Caller.MyInvocation.ExpectingInput) { return $false }
    return ($null -eq $QueryParams -or $QueryParams.Count -eq 0)
}
