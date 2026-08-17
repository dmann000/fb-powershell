function Assert-PfbSelectorNotCoerced {
    <#
    .SYNOPSIS
        Reject a selector value that is the ToString() of a whole piped object.
    .DESCRIPTION
        PowerShell resolves pipeline binding in FOUR passes: ByValue-without-coercion,
        ByPropertyName-without-coercion, ByValue-WITH-coercion, then
        ByPropertyName-WITH-coercion. A parameter that declares ValueFromPipeline is
        therefore reachable at pass 3 by ANY object, whatever its shape.

        Seventeen read cmdlets declare ValueFromPipeline on a name selector so that a
        bare string can be piped ('policy1' | Get-PfbNfsExportRule). When the piped item
        is an OBJECT that matches none of the cmdlet's parameters by property name,
        pass 2 misses and pass 3 fires, ToString()-ing the entire PSCustomObject into the
        [string[]] selector. The result is a garbage filter such as

            policy_names=@{name=nfs-01; enabled=True; rules=}

        which the array answers with HTTP 200 and the UNFILTERED collection, so the
        caller believes they are looking at one policy's rules when they are looking at
        every policy's rules. That silent mis-filtering is the issue-90 defect.

        Several of these cmdlets Add-Member a lifted top-level property (PolicyName,
        RoleName, GroupName) onto the items they return, which makes the self-chain
        (Get-PfbNfsExportRule | Get-PfbNfsExportRule) bind at pass 2 and never reach this
        guard. The lift cannot help the CROSS-endpoint chain
        (Get-PfbNfsExportPolicy | Get-PfbNfsExportRule), because a policy item carries
        `name`, not `PolicyName`. That residual is what this guard closes.

        Note also that removing ValueFromPipeline does not make coercion impossible: a
        ValueFromPipelineByPropertyName-only parameter whose ALIAS matches an
        object-valued property still binds that object stringified at pass 4. This guard
        covers that case too, since it inspects the bound value rather than the pass that
        produced it.

        Deliberately called imperatively from each cmdlet's process block rather than
        wired as [ValidateScript({ ... })]. That was tried and reverted under issue #64:
        a ValidateScript failure on a PIPELINE-bound argument is a NON-terminating
        per-item binding error, so the cmdlet's end block still runs and still issues the
        request -- with no selector key at all, i.e. the silently-unfiltered result this
        guard exists to eliminate. The imperative throw terminates the pipeline, which is
        the required behaviour.

        Returns NOTHING on success, matching Assert-PfbAdminNameNotCoerced. Do not add a
        `return $true`: callers invoke this bare, so a return value leaks into each
        cmdlet's success stream.
    .PARAMETER Value
        The bound selector value. May be $null, a scalar, or a collection; every element
        is checked. $null and an empty collection are accepted silently -- a parameter
        that was never bound is not a defect.
    .PARAMETER ParameterName
        The parameter name WITHOUT its leading dash, e.g. 'PolicyName'. The dash is added
        when the message is built.
    .PARAMETER Hint
        Caller-facing, cmdlet-specific advice naming the property to pipe instead. Each
        call site writes its own against what that family's producer actually returns.
    #>
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] [object]$Value,
        [Parameter(Mandatory)] [string]$ParameterName,
        [Parameter(Mandatory)] [string]$Hint
    )

    if ($null -eq $Value) { return }

    foreach ($v in @($Value)) {
        # .Contains() rather than -like: a literal test needs no wildcard semantics, and
        # .Contains() cannot be broken by interpolating caller text into a pattern.
        if ($v -is [string] -and $v.Contains('@{')) {
            # Built in one -f call: the format operator binds tighter than '+', so
            # splitting this across concatenated literals silently formats only the last.
            $message = '-{0} received a stringified object (''{1}'') instead of a name. ' +
                       'A piped object that matches none of this cmdlet''s parameters by property ' +
                       'name is coerced whole into -{0}, which sends a garbage filter and returns ' +
                       'the UNFILTERED collection. {2}'
            throw ($message -f $ParameterName, $v, $Hint)
        }
    }
}
