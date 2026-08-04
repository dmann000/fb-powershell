function Assert-PfbRemoteNameNotCoerced {
    <#
    .SYNOPSIS
        Reject a -RemoteName value that is the ToString() of a whole piped object.
    .DESCRIPTION
        PowerShell resolves pipeline binding in three passes: ByValue-without-coercion,
        then ByPropertyName-without-coercion, then ByValue-WITH-coercion.

        Get-PfbArrayConnectionPath and Get-PfbArrayConnectionPerformanceReplication have no -Id
        parameter at all, so a piped connection object falls through to pass 3 and the entire
        PSCustomObject is ToString()-ed into [string[]]$RemoteName. Get-/Remove-PfbArrayConnection
        do expose -Id and usually bind at pass 2 on it, but that is a property of the piped
        OBJECT, not of the cmdlet: pipe anything lacking id/name/remoteName and pass 3 fires
        there too. (Update-PfbArrayConnection is genuinely immune -- neither of its parameters
        declares ValueFromPipeline, so pass 3 is unreachable and the guard would be dead code.)

        Either way the result is a garbage filter such as

            remote_names=@{id=10314f42-aaaa; status=connected; remote=}

        Before issue #64 the key was the unrecognised (and therefore silently ignored) names=, so
        this returned every record unfiltered. Now that remote_names= is live, the array rejects
        it with "Array connection does not exist." This helper turns that into an actionable,
        module-level failure instead of a confusing server-side one.

        -RemoteName by value with plain strings ('FB-B','FB-C' | Get-PfbArrayConnectionPath) is
        unaffected, as is binding by property name.

        Deliberately called imperatively from each cmdlet's process block rather than wired as
        [ValidateScript({ Assert-PfbRemoteNameNotCoerced $_ })] like Assert-PfbSafeName. That was
        tried and reverted: a ValidateScript failure on a PIPELINE-bound argument is a
        NON-terminating per-item binding error, so the cmdlet's end block still runs and still
        issues the request -- with no remote_names key at all, i.e. the silently-unfiltered
        result that issue #64 exists to eliminate. Verified on both editions. The imperative
        throw terminates the pipeline, which is the required behaviour.
    #>
    param([Parameter(Mandatory)] [object]$Value)

    foreach ($v in @($Value)) {
        if ($v -is [string] -and $v -like '*@{*') {
            throw ("-RemoteName received a stringified object ('{0}') instead of a remote array name. " -f $v) +
                  'A piped object that binds to neither -Id nor a name property is coerced whole into ' +
                  '-RemoteName. Pipe the remote name instead, e.g. ' +
                  'Get-PfbArrayConnection | Select-Object -ExpandProperty remote | ' +
                  'Select-Object -ExpandProperty name | Get-PfbArrayConnectionPath, or pass -RemoteName explicitly.'
        }
    }
    return $true
}
