function Update-PfbLifecycleRule {
    <#
    .SYNOPSIS
        Updates an object lifecycle rule on the FlashBlade.
    .DESCRIPTION
        Modifies the configuration of an existing lifecycle rule on the FlashBlade,
        such as changing the prefix filter, expiration period, or enabled status.
    .PARAMETER Name
        The name of the lifecycle rule to update.
    .PARAMETER Id
        The ID of the lifecycle rule to update.
    .PARAMETER BucketIds
        The IDs of the buckets whose lifecycle rules to update.
    .PARAMETER BucketNames
        The names of the buckets whose lifecycle rules to update.
    .PARAMETER ConfirmDate
        The confirmation timestamp required to apply a change that affects existing objects.
    .PARAMETER AbortIncompleteMultipartUploadsAfter
        Duration of time after which incomplete multipart uploads will be aborted.
    .PARAMETER Enabled
        If set to `true`, this rule will be enabled.
    .PARAMETER KeepCurrentVersionFor
        Time after which current versions will be marked expired.
    .PARAMETER KeepCurrentVersionUntil
        Time after which current versions will be marked expired.
    .PARAMETER KeepPreviousVersionFor
        Time after which previous versions will be marked expired.
    .PARAMETER Prefix
        Object key prefix identifying one or more objects in the bucket.
    .PARAMETER Attributes
        A hashtable of lifecycle rule attributes to update, such as prefix,
        keep_previous_version_for, or enabled. Mutually exclusive with the individual typed
        parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Update-PfbLifecycleRule -Name "expire-logs-30d" -KeepPreviousVersionFor 5184000000

        Updates the retention period of the lifecycle rule to 60 days using a typed parameter.
    .EXAMPLE
        Update-PfbLifecycleRule -Name "cleanup" -Enabled $false

        Disables the lifecycle rule named 'cleanup'.
    .EXAMPLE
        Update-PfbLifecycleRule -Name "archive" -Prefix "old/" -KeepPreviousVersionFor 7776000000

        Updates the prefix filter and retention period of the 'archive' rule.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        # Constraint 17: newly added QUERY parameters are declared bare, NOT in the
        # *Individual sets -- they are orthogonal to the request body and must stay usable
        # alongside -Attributes.
        [Parameter()]
        [string[]]$BucketIds,

        [Parameter()]
        [string[]]$BucketNames,

        [Parameter()]
        [long]$ConfirmDate,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$AbortIncompleteMultipartUploadsAfter,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$Enabled,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$KeepCurrentVersionFor,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$KeepCurrentVersionUntil,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [long]$KeepPreviousVersionFor,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Prefix,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }

        # Every value-carrying query parameter is guarded by ContainsKey, never truthiness --
        # see the canonical explanation in Update-PfbAdmin.ps1.
        if ($PSBoundParameters.ContainsKey('BucketIds'))   { $queryParams['bucket_ids']   = $BucketIds -join ',' }
        if ($PSBoundParameters.ContainsKey('BucketNames')) { $queryParams['bucket_names'] = $BucketNames -join ',' }
        if ($PSBoundParameters.ContainsKey('ConfirmDate')) { $queryParams['confirm_date'] = $ConfirmDate }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('AbortIncompleteMultipartUploadsAfter')) { $body['abort_incomplete_multipart_uploads_after'] = $AbortIncompleteMultipartUploadsAfter }
            if ($PSBoundParameters.ContainsKey('Enabled'))                              { $body['enabled']                                    = $Enabled }
            if ($PSBoundParameters.ContainsKey('KeepCurrentVersionFor'))                { $body['keep_current_version_for']                  = $KeepCurrentVersionFor }
            if ($PSBoundParameters.ContainsKey('KeepCurrentVersionUntil'))              { $body['keep_current_version_until']                = $KeepCurrentVersionUntil }
            if ($PSBoundParameters.ContainsKey('KeepPreviousVersionFor'))               { $body['keep_previous_version_for']                 = $KeepPreviousVersionFor }
            if ($PSBoundParameters.ContainsKey('Prefix'))                               { $body['prefix']                                     = $Prefix }
        }

        if ($PSCmdlet.ShouldProcess($target, 'Update lifecycle rule')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'lifecycle-rules' -Body $body -QueryParams $queryParams
        }
    }
}
