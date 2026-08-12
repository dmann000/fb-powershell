function Assert-PfbFileSystemReplicaLinkTransferNameNotCoerced {
    <#
    .SYNOPSIS
        Reject a -NameOrOwnerName value that is the ToString() of a whole piped object.
    .DESCRIPTION
        PowerShell resolves pipeline binding in three passes: ByValue-without-coercion,
        then ByPropertyName-without-coercion, then ByValue-WITH-coercion. An object that
        exposes neither an id nor a name-or-owner-name property falls through to the last
        pass and is ToString()-ed into [string[]]$NameOrOwnerName. That would send a
        stringified object such as @{status=...} as a names_or_owner_names filter.

        The imperative throw is deliberate. A ValidateScript failure on a pipeline-bound
        argument is non-terminating, so the cmdlet's end block can still issue an
        unfiltered request. This guard terminates before Invoke-PfbApiRequest runs.
    #>
    param([Parameter(Mandatory)] [object]$Value)

    foreach ($v in @($Value)) {
        if ($v -is [string] -and $v.Contains('@{')) {
            throw ("-NameOrOwnerName received a stringified object ('{0}') instead of a snapshot or owning file-system name. " -f $v) +
                  'A piped object that binds to neither -Id nor a name property is coerced whole into ' +
                  '-NameOrOwnerName. Pipe the snapshot or file-system name instead, or pass -NameOrOwnerName explicitly.'
        }
    }
    return $true
}
