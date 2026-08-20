function Assert-PfbAdminNameNotCoerced {
    <#
    .SYNOPSIS
        Reject a -Name value that is the ToString() of a whole piped object.
    .DESCRIPTION
        PowerShell resolves pipeline binding in three passes: ByValue-without-coercion,
        then ByPropertyName-without-coercion, then ByValue-WITH-coercion.

        A Get-PfbApiToken row exposes only `admin`, `api_token` and `context` at the top
        level -- the administrator's name is nested at .admin.name -- so piping one into
        Get-PfbApiToken, New-PfbApiToken or Remove-PfbApiToken matches neither pass 1 nor
        pass 2, and the entire PSCustomObject is ToString()-ed into $Name at pass 3 (into
        the single element of [string[]]$Name on Get-). The result is a garbage filter such
        as

            admin_names=@{admin=; api_token=}

        On Remove-PfbApiToken that reaches a DELETE with ConfirmImpact High, which is why
        this is worth a module-level failure rather than a confusing server-side one.

        Plain strings ('ops-admin','svc' | Remove-PfbApiToken) are unaffected, as is
        binding by property name from a Get-PfbAdmin object.

        Called by all three /admins/api-tokens cmdlets. New- and Remove- take a scalar
        [string]$Name and call it once per pipeline item; Get- takes [string[]]$Name and
        calls it per element. -Value therefore accepts either a scalar or a collection and
        checks each member.

        Deliberately called imperatively from each cmdlet's process block rather than wired
        as [ValidateScript({ ... })]. That was tried and reverted under issue #64: a
        ValidateScript failure on a PIPELINE-bound argument is a NON-terminating per-item
        binding error, so the cmdlet continues and still issues the request -- reinstating
        the silent-misbinding class this guard exists to remove. The imperative throw
        terminates the pipeline, which is the required behaviour.

        This imperative assertion helper returns NOTHING on success and reports failure
        only through a terminating throw. Callers invoke it bare, so any success-stream
        value it returned would leak into the cmdlet's own output.
    #>
    param([Parameter(Mandatory)] [object]$Value)

    foreach ($v in @($Value)) {
        if ($v -is [string] -and $v.Contains('@{')) {
            throw ("-Name received a stringified object ('{0}') instead of an administrator name. " -f $v) +
                  'Get-PfbApiToken output has no top-level name property -- the administrator name is ' +
                  'nested at .admin.name -- so a piped API-token object is coerced whole into -Name. ' +
                  'Pipe the name instead, e.g. Get-PfbApiToken | ForEach-Object { $_.admin.name } | ' +
                  'Remove-PfbApiToken, or pass -Name explicitly.'
        }
    }
}
