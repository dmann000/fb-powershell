function Assert-PfbRemoteNameNotCoerced {
    <#
    .SYNOPSIS
        Reject a -RemoteName value that is the ToString() of a whole piped object.
    .DESCRIPTION
        PowerShell resolves pipeline binding in three passes: ByValue-without-coercion,
        then ByPropertyName-without-coercion, then ByValue-WITH-coercion.

        Array-connection cmdlets that expose an -Id parameter (Get-/Remove-/Update-PfbArrayConnection)
        bind a piped connection object at pass 2, on id. Get-PfbArrayConnectionPath and
        Get-PfbArrayConnectionPerformanceReplication have no -Id parameter at all, so a piped
        connection object falls through to pass 3 and the entire PSCustomObject is ToString()-ed
        into [string[]]$RemoteName, producing a garbage filter such as

            remote_names=@{id=10314f42-aaaa; status=connected; remote=}

        Before issue #64 the key was the unrecognised (and therefore silently ignored) names=, so
        this returned every record unfiltered. Now that remote_names= is live, the array rejects
        it with "Array connection does not exist." This helper turns that into an actionable,
        module-level failure instead of a confusing server-side one.

        -RemoteName by value with plain strings ('FB-B','FB-C' | Get-PfbArrayConnectionPath) is
        unaffected, as is binding by property name.
    #>
    param([Parameter(Mandatory)] [object]$Value)

    foreach ($v in @($Value)) {
        if ($v -is [string] -and $v -like '*@{*') {
            throw ("-RemoteName received a stringified object ('{0}') instead of a remote array name. " -f $v) +
                  'This cmdlet has no -Id parameter, so piping an array-connection object coerces the ' +
                  'whole object into -RemoteName. Pipe the remote name instead, e.g. ' +
                  'Get-PfbArrayConnection | Select-Object -ExpandProperty remote | ' +
                  'Select-Object -ExpandProperty name | Get-PfbArrayConnectionPath, or pass -RemoteName explicitly.'
        }
    }
    return $true
}
