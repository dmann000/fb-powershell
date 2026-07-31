function Update-PfbObjectStoreRemoteCredential {
    <#
    .SYNOPSIS
        Updates an existing object store remote credential on the FlashBlade.
    .DESCRIPTION
        Modifies the properties of an existing remote credential, such as
        rotating the access key or secret key used for replication to an
        external S3-compatible target.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the remote credential to update.
    .PARAMETER Id
        The ID of the remote credential to update.
    .PARAMETER AccessKeyId
        Access Key ID to be used when connecting to a remote object store.
    .PARAMETER NewName
        A new user-specified name for the remote credential.
    .PARAMETER Remote
        Reference to the associated remote, which can either be a target or remote array.
    .PARAMETER SecretAccessKey
        Secret Access Key to be used when connecting to a remote object store. Treated as
        sensitive: never logged or echoed via -Verbose.
    .PARAMETER Attributes
        A hashtable of credential properties to update, such as access_key_id
        and secret_access_key. Mutually exclusive with the individual typed
        parameters above.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbObjectStoreRemoteCredential -Name "s3-repl-cred" -SecretAccessKey "newSecretKeyValue12345EXAMPLEKEY"

        Rotates the secret access key using a typed parameter.
    .EXAMPLE
        Update-PfbObjectStoreRemoteCredential -Name "s3-repl-cred" -Attributes @{
            secret_access_key = "newSecretKeyValue12345EXAMPLEKEY"
        }
        Rotates the secret access key for the specified remote credential.
    .EXAMPLE
        Update-PfbObjectStoreRemoteCredential -Id "10314f42-020d-7080-8013-000ddt400090" -Attributes @{
            access_key_id = "AKIAI44QH8DHBEXAMPLE"
            secret_access_key = "je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY"
        }
        Updates both access key fields by credential ID.
    .EXAMPLE
        Update-PfbObjectStoreRemoteCredential -Name "backup-target" -Attributes @{
            access_key_id = "AKIAIOSFODNN7EXAMPLE"
        }
        Updates the access key ID for the backup-target credential.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$AccessKeyId,

        # EXCEPTION: the wire field is literally `name` (a rename), so the parameter is
        # -NewName, never -RemoteCredentialName -- see Global Constraint on the `name` field.
        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Remote,

        # Sensitive: no default value, never echoed via Write-Verbose.
        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$SecretAccessKey,

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
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('AccessKeyId')) { $body['access_key_id'] = $AccessKeyId }
            if ($PSBoundParameters.ContainsKey('NewName'))     { $body['name']          = $NewName }

            # Constraint 8(a): remote is a SCALAR REFERENCE (item schema is {id, name,
            # resource_type}), so the parameter is [string] and the projection is assigned
            # INLINE -- constraint 7 forbids a local variable here.
            if ($PSBoundParameters.ContainsKey('Remote')) { $body['remote'] = @{ name = $Remote } }

            if ($PSBoundParameters.ContainsKey('SecretAccessKey')) { $body['secret_access_key'] = $SecretAccessKey }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update object store remote credential')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'object-store-remote-credentials' -Body $body -QueryParams $queryParams
        }
    }
}
