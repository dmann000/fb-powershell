#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Every cmdlet in Task 1 scope. All of them publish [string[]]$Name and
# [string[]]$BucketName, and none of them may still publish MemberName.
$script:metadataCases = @(
    @{ Cmdlet = 'Get-PfbBucketAuditFilter' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicy' }
    @{ Cmdlet = 'Get-PfbBucketAccessPolicy' }
    @{ Cmdlet = 'Remove-PfbBucketAuditFilter' }
    @{ Cmdlet = 'Remove-PfbBucketCorsPolicy' }
    @{ Cmdlet = 'Get-PfbBucketAccessPolicyRule' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicyRule' }
    @{ Cmdlet = 'New-PfbBucketAuditFilter' }
)

# Cmdlets whose -Name / -BucketName selectors are exercised on the wire.
# New-PfbBucketAuditFilter is excluded: POST buckets/audit-filters declares
# `names` as required and carries no bucket identity in its body, so its call
# shape is Name+BucketName combined and is covered by its own Context below.
$script:selectorCases = @(
    @{ Cmdlet = 'Get-PfbBucketAuditFilter';       NameKey = 'names'; BucketKey = 'bucket_names'; Endpoint = 'buckets/audit-filters'; Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicy';        NameKey = 'names'; BucketKey = 'bucket_names'; Endpoint = 'buckets/cross-origin-resource-sharing-policies'; Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketAccessPolicy';      NameKey = 'names'; BucketKey = 'bucket_names'; Endpoint = 'buckets/bucket-access-policies'; Method = 'GET' }
    @{ Cmdlet = 'Remove-PfbBucketAuditFilter';    NameKey = 'names'; BucketKey = 'bucket_names'; Endpoint = 'buckets/audit-filters'; Method = 'DELETE' }
    @{ Cmdlet = 'Remove-PfbBucketCorsPolicy';     NameKey = 'names'; BucketKey = 'bucket_names'; Endpoint = 'buckets/cross-origin-resource-sharing-policies'; Method = 'DELETE' }
    @{ Cmdlet = 'Get-PfbBucketAccessPolicyRule';  NameKey = 'names'; BucketKey = 'bucket_names'; Endpoint = 'buckets/bucket-access-policies/rules'; Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicyRule';    NameKey = 'names'; BucketKey = 'bucket_names'; Endpoint = 'buckets/cross-origin-resource-sharing-policies/rules'; Method = 'GET' }
)

# The two rule endpoints are the only ones that declare `policy_names`.
$script:ruleCases = @(
    @{ Cmdlet = 'Get-PfbBucketAccessPolicyRule'; Endpoint = 'buckets/bucket-access-policies/rules' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicyRule';   Endpoint = 'buckets/cross-origin-resource-sharing-policies/rules' }
)

# The five cmdlets that previously carried -MemberId / `member_ids`. The
# endpoints declare `bucket_ids`, never `member_ids`.
$script:bucketIdCases = @(
    @{ Cmdlet = 'Get-PfbBucketAuditFilter';    Endpoint = 'buckets/audit-filters'; Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicy';     Endpoint = 'buckets/cross-origin-resource-sharing-policies'; Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketAccessPolicy';   Endpoint = 'buckets/bucket-access-policies'; Method = 'GET' }
    @{ Cmdlet = 'Remove-PfbBucketAuditFilter'; Endpoint = 'buckets/audit-filters'; Method = 'DELETE' }
    @{ Cmdlet = 'Remove-PfbBucketCorsPolicy';  Endpoint = 'buckets/cross-origin-resource-sharing-policies'; Method = 'DELETE' }
)

# `policy_names` / `policy_ids` are declared only on the /rules variants, so
# these cmdlets must not publish them at all.
$script:noPolicySelectorCases = @(
    @{ Cmdlet = 'Get-PfbBucketAccessPolicy'; Forbidden = 'PolicyName' }
    @{ Cmdlet = 'Get-PfbBucketAccessPolicy'; Forbidden = 'PolicyId' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicy';   Forbidden = 'PolicyName' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicy';   Forbidden = 'PolicyId' }
    @{ Cmdlet = 'Remove-PfbBucketCorsPolicy'; Forbidden = 'PolicyName' }
    # Task 1b: same rule on the access-policy parent operations.
    @{ Cmdlet = 'Remove-PfbBucketAccessPolicy'; Forbidden = 'PolicyName' }
    @{ Cmdlet = 'Remove-PfbBucketAccessPolicy'; Forbidden = 'PolicyId' }
    @{ Cmdlet = 'New-PfbBucketAccessPolicy';    Forbidden = 'PolicyName' }
    @{ Cmdlet = 'New-PfbBucketCorsPolicy';      Forbidden = 'PolicyName' }
)

# Pipeline binding: a bare piped string must mean "bucket" on the destructive
# cmdlets exactly as it does on their Get-* siblings.
$script:pipelineCases = @(
    @{ Cmdlet = 'Get-PfbBucketAuditFilter';      Endpoint = 'buckets/audit-filters'; Method = 'GET' }
    @{ Cmdlet = 'Remove-PfbBucketAuditFilter';   Endpoint = 'buckets/audit-filters'; Method = 'DELETE' }
    @{ Cmdlet = 'Remove-PfbBucketCorsPolicy';    Endpoint = 'buckets/cross-origin-resource-sharing-policies'; Method = 'DELETE' }
    @{ Cmdlet = 'Remove-PfbBucketAccessPolicy';  Endpoint = 'buckets/bucket-access-policies'; Method = 'DELETE' }
)

# ---------------------------------------------------------------------------
# Task 1b -- the remaining bucket selector surface.
# ---------------------------------------------------------------------------

# The five siblings that still carried -MemberName / `member_names`. Verified
# per endpoint against tools/specs/fb2.0-2.28: `member_names` and `member_ids`
# are declared on NONE of these operations in ANY version, while `bucket_names`
# and `bucket_ids` have been declared since each endpoint first appeared.
$script:task1bMemberCases = @(
    @{ Cmdlet = 'New-PfbBucketAccessPolicy' }
    @{ Cmdlet = 'New-PfbBucketAccessPolicyRule' }
    @{ Cmdlet = 'New-PfbBucketCorsPolicy' }
    @{ Cmdlet = 'Remove-PfbBucketAccessPolicy' }
    @{ Cmdlet = 'Update-PfbBucketAuditFilter' }
)

# The four bucket Get-* cmdlets that published a generic -Id emitting `ids`.
# Verified INDIVIDUALLY: none of these four GET operations declares `ids` in
# any version 2.12-2.28 (2.12 is where all four paths first appear), so -Id
# silently returned the unfiltered collection. `names` IS declared on all
# four, so -Name survives.
$script:deadIdCases = @(
    @{ Cmdlet = 'Get-PfbBucketAccessPolicy';     Endpoint = 'buckets/bucket-access-policies';                       Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicy';       Endpoint = 'buckets/cross-origin-resource-sharing-policies';       Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketAccessPolicyRule'; Endpoint = 'buckets/bucket-access-policies/rules';                 Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicyRule';   Endpoint = 'buckets/cross-origin-resource-sharing-policies/rules'; Method = 'GET' }
)

# POST /buckets/bucket-access-policies and
# POST /buckets/cross-origin-resource-sharing-policies declare ONLY
# bucket_names / bucket_ids (plus context_names from 2.17). Neither `names`
# nor `policy_names` exists on either, so these two cmdlets carry no
# policy-level and no name-level selector at all.
$script:bucketOnlyPostCases = @(
    @{ Cmdlet = 'New-PfbBucketAccessPolicy'; Endpoint = 'buckets/bucket-access-policies' }
    @{ Cmdlet = 'New-PfbBucketCorsPolicy';   Endpoint = 'buckets/cross-origin-resource-sharing-policies' }
)

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{
        Endpoint   = 'fb.example.test'
        ApiVersion = '2.0'
        AuthToken  = 'x'
    }
}

Describe 'Bucket policy and filter selectors (#90)' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'Parameter surface' {
        It '<Cmdlet> removes MemberName and publishes BucketName' -ForEach $script:metadataCases {
            $keys = (Get-Command $Cmdlet).Parameters.Keys
            $keys | Should -Not -Contain 'MemberName'
            $keys | Should -Contain 'BucketName'
        }

        It '<Cmdlet> publishes Name and BucketName as [string[]]' -ForEach $script:metadataCases {
            $parameters = (Get-Command $Cmdlet).Parameters
            $parameters.Keys | Should -Contain 'Name'
            $parameters['Name'].ParameterType.FullName | Should -Be 'System.String[]'
            $parameters['BucketName'].ParameterType.FullName | Should -Be 'System.String[]'
        }

        It '<Cmdlet> replaces MemberId with a [string[]] BucketId' -ForEach $script:bucketIdCases {
            $parameters = (Get-Command $Cmdlet).Parameters
            $parameters.Keys | Should -Not -Contain 'MemberId'
            $parameters.Keys | Should -Contain 'BucketId'
            $parameters['BucketId'].ParameterType.FullName | Should -Be 'System.String[]'
        }

        It '<Cmdlet> does not publish <Forbidden> (undeclared on this endpoint)' -ForEach $script:noPolicySelectorCases {
            (Get-Command $Cmdlet).Parameters.Keys | Should -Not -Contain $Forbidden
        }
    }

    Context 'Wire keys' {
        It '<Cmdlet> maps Name to <NameKey> with exact endpoint, method, and no member_names' -ForEach $script:selectorCases {
            $parameters = @{ Name = 'pslivetest-selector-a'; Array = $script:fakeArray }
            if ($Cmdlet -like 'Remove-*') { $parameters['Confirm'] = $false }
            & $Cmdlet @parameters

            $expectedMethod = $Method
            $expectedEndpoint = $Endpoint
            $expectedNameKey = $NameKey
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and $QueryParams[$expectedNameKey] -eq 'pslivetest-selector-a' -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }

        It '<Cmdlet> maps BucketName to <BucketKey> with exact endpoint, method, and no member_names' -ForEach $script:selectorCases {
            $parameters = @{ BucketName = 'pslivetest-bucket-a'; Array = $script:fakeArray }
            if ($Cmdlet -like 'Remove-*') { $parameters['Confirm'] = $false }
            & $Cmdlet @parameters

            $expectedMethod = $Method
            $expectedEndpoint = $Endpoint
            $expectedBucketKey = $BucketKey
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and $QueryParams[$expectedBucketKey] -eq 'pslivetest-bucket-a' -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }

        It '<Cmdlet> maps BucketId to bucket_ids and never member_ids' -ForEach $script:bucketIdCases {
            $parameters = @{ BucketId = 'pslivetest-bucket-id-a'; Array = $script:fakeArray }
            if ($Cmdlet -like 'Remove-*') { $parameters['Confirm'] = $false }
            & $Cmdlet @parameters

            $expectedMethod = $Method
            $expectedEndpoint = $Endpoint
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and $QueryParams['bucket_ids'] -eq 'pslivetest-bucket-id-a' -and
                -not $QueryParams.ContainsKey('member_ids')
            }
        }

        It '<Cmdlet> maps PolicyName to policy_names without member_names' -ForEach $script:ruleCases {
            & $Cmdlet -PolicyName 'pslivetest-selector-a' -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and $QueryParams.Count -eq 1 -and
                $QueryParams['policy_names'] -eq 'pslivetest-selector-a' -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }
    }

    Context 'Pipeline binding' {
        It '<Cmdlet> binds a bare piped string to BucketName' -ForEach $script:pipelineCases {
            $parameters = @{ Array = $script:fakeArray }
            if ($Cmdlet -like 'Remove-*') { $parameters['Confirm'] = $false }
            'pslivetest-bucket-a' | & $Cmdlet @parameters

            $expectedMethod = $Method
            $expectedEndpoint = $Endpoint
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and $QueryParams['bucket_names'] -eq 'pslivetest-bucket-a'
            }
        }
    }

    # Get-PfbBucket | Get-PfbBucketAccessPolicy is a chain a user would naturally write. No
    # producer emits `BucketName` (the bucket item's own selector is `name`, and -Name here is
    # not pipeline-bound), so the bucket object fell through to by-value coercion and
    # bucket_names=@{...whole bucket...} went on the wire: HTTP 200 and the UNFILTERED policy
    # list. ValueFromPipeline stays, so bare-string piping keeps working; the guard rejects the
    # coerced object instead.
    Context 'Coercion guard on the bucket Get-* selectors (#90)' {
        $script:bucketGuardCases = @(
            @{ Cmdlet = 'Get-PfbBucketAccessPolicy' }
            @{ Cmdlet = 'Get-PfbBucketAccessPolicyRule' }
            @{ Cmdlet = 'Get-PfbBucketAuditFilter' }
            @{ Cmdlet = 'Get-PfbBucketCorsPolicy' }
            @{ Cmdlet = 'Get-PfbBucketCorsPolicyRule' }
        )

        It '<Cmdlet> rejects a coerced bucket object before any request is built' -ForEach $script:bucketGuardCases {
            { [PSCustomObject]@{ name = 'pslivetest-bucket-a'; destroyed = $false } |
                & $Cmdlet -Array $script:fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*stringified object*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It '<Cmdlet> names -BucketName and Get-PfbBucket in the guard message' -ForEach $script:bucketGuardCases {
            { [PSCustomObject]@{ name = 'pslivetest-bucket-a' } |
                & $Cmdlet -Array $script:fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*-BucketName*'
            { [PSCustomObject]@{ name = 'pslivetest-bucket-a' } |
                & $Cmdlet -Array $script:fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Get-PfbBucket*'
        }

        It '<Cmdlet> still binds a bare piped string to bucket_names' -ForEach $script:bucketGuardCases {
            { 'pslivetest-bucket-a' | & $Cmdlet -Array $script:fakeArray } | Should -Not -Throw

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['bucket_names'] -eq 'pslivetest-bucket-a'
            }
        }
    }

    Context 'New-PfbBucketAuditFilter POST shape' {
        It 'sends the spec-required names alongside bucket_names, defaulting names from the bucket' {
            New-PfbBucketAuditFilter -BucketName 'pslivetest-bucket-a' -Attributes @{ actions = @('s3.GetObject') } -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'buckets/audit-filters' -and
                $QueryParams.Count -eq 2 -and
                $QueryParams['names'] -eq 'pslivetest-bucket-a' -and
                $QueryParams['bucket_names'] -eq 'pslivetest-bucket-a' -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }

        It 'accepts Name and BucketName in one invocation' {
            New-PfbBucketAuditFilter -BucketName 'pslivetest-bucket-a' -Name 'pslivetest-filter-a' -Attributes @{ actions = @('s3.GetObject') } -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'buckets/audit-filters' -and
                $QueryParams.Count -eq 2 -and
                $QueryParams['names'] -eq 'pslivetest-filter-a' -and
                $QueryParams['bucket_names'] -eq 'pslivetest-bucket-a'
            }
        }

        It 'passes the supplied attributes through as the POST body' {
            New-PfbBucketAuditFilter -BucketName 'pslivetest-bucket-a' -Attributes @{ actions = @('s3.GetObject'); s3_prefixes = @('logs/') } -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Body['actions'] -contains 's3.GetObject' -and
                $Body['s3_prefixes'] -contains 'logs/' -and
                -not $Body.ContainsKey('bucket_names') -and
                -not $Body.ContainsKey('names')
            }
        }
    }

    # =======================================================================
    # Task 1b
    # =======================================================================

    Context 'Task 1b -- remaining member selector surface' {
        It '<Cmdlet> publishes neither MemberName nor MemberId, and does publish BucketName' -ForEach $script:task1bMemberCases {
            $keys = (Get-Command $Cmdlet).Parameters.Keys
            $keys | Should -Not -Contain 'MemberName'
            $keys | Should -Not -Contain 'MemberId'
            $keys | Should -Contain 'BucketName'
        }

        # NOTE: deliberately no behavioural "rejects -MemberName at bind time" case here.
        # Every one of these five cmdlets carries at least one other Mandatory parameter,
        # so an invocation supplying only -MemberName can drop into the interactive
        # "Supply values for parameters" prompt and hang a non-interactive run. Parameter
        # absence from the metadata is the same guarantee -- PowerShell cannot bind a name
        # it does not publish -- without the hang risk. Do not "fix" this by adding one.
        It '<Cmdlet> exposes MemberName/MemberId in no parameter set' -ForEach $script:task1bMemberCases {
            foreach ($set in (Get-Command $Cmdlet).ParameterSets) {
                @($set.Parameters.Name) | Should -Not -Contain 'MemberName'
                @($set.Parameters.Name) | Should -Not -Contain 'MemberId'
            }
        }
    }

    Context 'Task 1b -- New-PfbBucketAccessPolicy / New-PfbBucketCorsPolicy POST shape' {
        It '<Cmdlet> emits exactly bucket_names, with no member_names and no policy_names' -ForEach $script:bucketOnlyPostCases {
            $expectedEndpoint = $Endpoint
            $expectedBucket   = 'pslivetest-bucket-a'

            & $Cmdlet -BucketName $expectedBucket -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['bucket_names'] -eq $expectedBucket -and
                -not $QueryParams.ContainsKey('member_names') -and
                -not $QueryParams.ContainsKey('policy_names') -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        # NOTE: metadata-only, deliberately. -BucketName is Mandatory on both of these
        # POST cmdlets, so a behavioural "pipe an unbindable object" case can drop into
        # the interactive "Supply values for parameters" prompt and hang a
        # non-interactive run -- the same hazard documented on Remove-PfbOpenFile in
        # Tests/PfbDeadSelectorRemoval.Tests.ps1. The absence of bare ValueFromPipeline
        # from the attribute metadata is the same guarantee without the hang risk.
        # Do not "fix" this by adding a piped-object case.
        It '<Cmdlet> declares bare ValueFromPipeline on NO parameter at all' -ForEach $script:bucketOnlyPostCases {
            $piped = @((Get-Command $Cmdlet).Parameters.Values |
                ForEach-Object { $_.Attributes } |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.ValueFromPipeline })
            $piped | Should -Not -Contain $true
        }

        It '<Cmdlet> keeps ValueFromPipelineByPropertyName on BucketName' -ForEach $script:bucketOnlyPostCases {
            $paramAttrs = @((Get-Command $Cmdlet).Parameters['BucketName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            @($paramAttrs | ForEach-Object { $_.ValueFromPipelineByPropertyName }) | Should -Contain $true
            @($paramAttrs | ForEach-Object { $_.ValueFromPipeline }) | Should -Not -Contain $true
        }

        It '<Cmdlet> publishes BucketName as a mandatory [string[]] and no Name' -ForEach $script:bucketOnlyPostCases {
            $parameters = (Get-Command $Cmdlet).Parameters
            $parameters.Keys | Should -Not -Contain 'Name'
            $parameters['BucketName'].ParameterType.FullName | Should -Be 'System.String[]'
            $mandatory = @($parameters['BucketName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory })
            $mandatory | Should -Contain $true
        }
    }

    Context 'Task 1b -- New-PfbBucketAccessPolicyRule POST shape' {
        It 'sends the spec-required names alongside bucket_names and policy_names' {
            $expectedName   = 'pslivetest-rule-a'
            $expectedBucket = 'pslivetest-bucket-a'
            $expectedPolicy = 'pslivetest-policy-a'

            # `effect` is readOnly in BucketAccessPolicyRulePost, so a caller cannot
            # send it -- the fixture uses only sendable properties. `principals` is an
            # OBJECT shaped { all: boolean }, not a string array.
            New-PfbBucketAccessPolicyRule -BucketName $expectedBucket -PolicyName $expectedPolicy `
                -Name $expectedName `
                -Attributes @{ actions = @('s3:GetObject'); principals = @{ all = $true } } `
                -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'buckets/bucket-access-policies/rules' -and
                $QueryParams.Count -eq 3 -and
                $QueryParams['names'] -eq $expectedName -and
                $QueryParams['bucket_names'] -eq $expectedBucket -and
                $QueryParams['policy_names'] -eq $expectedPolicy -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }

        It 'makes -Name mandatory, because POST .../rules declares names as required' {
            $nameParam = (Get-Command New-PfbBucketAccessPolicyRule).Parameters['Name']
            $nameParam | Should -Not -BeNullOrEmpty
            $nameParam.ParameterType.FullName | Should -Be 'System.String[]'
            $mandatory = @($nameParam.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory })
            $mandatory | Should -Contain $true
        }

        It 'keeps -Name reachable in every parameter set' {
            $command = Get-Command New-PfbBucketAccessPolicyRule
            foreach ($set in $command.ParameterSets) {
                @($set.Parameters.Name) | Should -Contain 'Name'
            }
        }

        It 'still passes -Attributes through as the POST body without leaking a query key into it' {
            New-PfbBucketAccessPolicyRule -BucketName 'pslivetest-bucket-a' -PolicyName 'pslivetest-policy-a' `
                -Name 'pslivetest-rule-a' `
                -Attributes @{ actions = @('s3:GetObject'); principals = @{ all = $true } } `
                -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['principals']['all'] -eq $true -and
                $Body['actions'] -contains 's3:GetObject' -and
                -not $Body.ContainsKey('effect') -and
                -not $Body.ContainsKey('bucket_names') -and
                -not $Body.ContainsKey('policy_names') -and
                -not $Body.ContainsKey('names')
            }
        }
    }

    # Coordinator ruling (round 3): POST
    # /buckets/cross-origin-resource-sharing-policies/rules declares
    # `bucket_ids bucket_names names* policy_names` in every version it exists in
    # (2.12-2.28; `context_names` joins at 2.17), where * is required:true. The
    # cmdlet previously sent NO query parameters at all, so it could not satisfy
    # the required `names` and was inoperable -- not merely mis-keyed. The request
    # body declares only allowed_headers/allowed_methods/allowed_origins and
    # carries no identity, so there is no overlap with the query keys.
    Context 'Task 1b/3 -- New-PfbBucketCorsPolicyRule POST shape' {
        It 'sends the spec-required names alongside bucket_names and policy_names' {
            $expectedName   = 'pslivetest-cors-rule-a'
            $expectedBucket = 'pslivetest-bucket-a'
            $expectedPolicy = 'pslivetest-cors-policy-a'

            New-PfbBucketCorsPolicyRule -BucketName $expectedBucket -PolicyName $expectedPolicy `
                -Name $expectedName -Attributes @{ allowed_origins = @('*'); allowed_methods = @('GET') } `
                -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'buckets/cross-origin-resource-sharing-policies/rules' -and
                $QueryParams.Count -eq 3 -and
                $QueryParams['names'] -eq $expectedName -and
                $QueryParams['bucket_names'] -eq $expectedBucket -and
                $QueryParams['policy_names'] -eq $expectedPolicy -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }

        It 'makes -Name mandatory, because POST .../rules declares names as required' {
            $nameParam = (Get-Command New-PfbBucketCorsPolicyRule).Parameters['Name']
            $nameParam | Should -Not -BeNullOrEmpty
            $nameParam.ParameterType.FullName | Should -Be 'System.String[]'
            $mandatory = @($nameParam.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory })
            $mandatory | Should -Contain $true
        }

        It 'keeps -Name reachable in every parameter set, so the required key can never be unsendable' {
            $command = Get-Command New-PfbBucketCorsPolicyRule
            @($command.ParameterSets).Count | Should -BeGreaterThan 0
            foreach ($set in $command.ParameterSets) {
                @($set.Parameters.Name) | Should -Contain 'Name'
            }
        }

        It 'emits the required names on every reachable parameter set' {
            # Review finding 5, addressed: each set gets a UNIQUE -Name value and is
            # asserted immediately after its own invocation, so this is a per-set
            # assertion rather than a total-invocation count. A set that failed to send
            # `names` can no longer be masked by a sibling set that did.
            $command = Get-Command New-PfbBucketCorsPolicyRule
            $setIndex = 0
            foreach ($set in $command.ParameterSets) {
                $setIndex++
                $expectedSetName = "pslivetest-set-$setIndex-name"
                $splat = @{
                    Array   = $script:fakeArray
                    Confirm = $false
                }
                foreach ($p in $set.Parameters) {
                    if (-not $p.IsMandatory) { continue }
                    switch ($p.Name) {
                        'Attributes' { $splat['Attributes'] = @{ allowed_origins = @('*') } }
                        'Name'       { $splat['Name'] = $expectedSetName }
                        default      { $splat[$p.Name] = "pslivetest-$($p.Name.ToLowerInvariant())" }
                    }
                }

                # Every Mandatory parameter of the set is bound, so this cannot fall into
                # the interactive "Supply values for parameters" prompt.
                New-PfbBucketCorsPolicyRule @splat

                Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest `
                    -Times 1 -Exactly -ParameterFilter {
                        $QueryParams.ContainsKey('names') -and
                        $QueryParams['names'] -eq $expectedSetName
                    }
            }

            $setIndex | Should -BeGreaterThan 0
        }

        It 'passes -Attributes through as the POST body without leaking a query key into it' {
            New-PfbBucketCorsPolicyRule -BucketName 'pslivetest-bucket-a' -PolicyName 'pslivetest-cors-policy-a' `
                -Name 'pslivetest-cors-rule-a' -Attributes @{ allowed_origins = @('*'); allowed_methods = @('GET') } `
                -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['allowed_origins'] -contains '*' -and
                $Body['allowed_methods'] -contains 'GET' -and
                -not $Body.ContainsKey('bucket_names') -and
                -not $Body.ContainsKey('policy_names') -and
                -not $Body.ContainsKey('names')
            }
        }

        It 'exposes no BucketId parameter, matching its access-policy-rule sibling' {
            # bucket_ids IS declared on this operation but no -BucketId parameter exists
            # here or on New-PfbBucketAccessPolicyRule; adding one is out of scope for
            # this ruling. This case pins the current surface so the omission stays a
            # deliberate, visible decision rather than drift.
            (Get-Command New-PfbBucketCorsPolicyRule).Parameters.Keys | Should -Not -Contain 'BucketId'
        }
    }

    Context 'Task 1b -- Remove-PfbBucketAccessPolicy DELETE shape' {
        It 'maps -Name to names only' {
            $expectedName = 'pslivetest-bucket-a/pslivetest-account:pslivetest-policy-a'

            Remove-PfbBucketAccessPolicy -Name $expectedName -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Endpoint -eq 'buckets/bucket-access-policies' -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['names'] -eq $expectedName -and
                -not $QueryParams.ContainsKey('member_names') -and
                -not $QueryParams.ContainsKey('policy_names')
            }
        }

        It 'maps -BucketId to bucket_ids only' {
            $expectedBucketId = 'pslivetest-bucket-id-a'

            Remove-PfbBucketAccessPolicy -BucketId $expectedBucketId -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Endpoint -eq 'buckets/bucket-access-policies' -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['bucket_ids'] -eq $expectedBucketId -and
                -not $QueryParams.ContainsKey('member_ids')
            }
        }

        It 'maps -BucketName to bucket_names only' {
            $expectedBucket = 'pslivetest-bucket-a'

            Remove-PfbBucketAccessPolicy -BucketName $expectedBucket -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Endpoint -eq 'buckets/bucket-access-policies' -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['bucket_names'] -eq $expectedBucket -and
                -not $QueryParams.ContainsKey('member_names') -and
                -not $QueryParams.ContainsKey('policy_names')
            }
        }
    }

    Context 'Task 1b -- Update-PfbBucketAuditFilter renamed selectors' {
        It 'maps -BucketName to bucket_names and defaults the required names from it' {
            $expectedBucket = 'pslivetest-bucket-a'

            Update-PfbBucketAuditFilter -BucketName $expectedBucket -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Endpoint -eq 'buckets/audit-filters' -and
                $QueryParams.Count -eq 2 -and
                $QueryParams['bucket_names'] -eq $expectedBucket -and
                $QueryParams['names'] -eq $expectedBucket -and
                -not $QueryParams.ContainsKey('member_names')
            }
        }

        It 'maps -BucketId to bucket_ids and takes the required names from -Name' {
            $expectedBucketId = 'pslivetest-bucket-id-a'
            $expectedName     = 'pslivetest-filter-a'

            Update-PfbBucketAuditFilter -BucketId $expectedBucketId -Name $expectedName `
                -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Endpoint -eq 'buckets/audit-filters' -and
                $QueryParams.Count -eq 2 -and
                $QueryParams['bucket_ids'] -eq $expectedBucketId -and
                $QueryParams['names'] -eq $expectedName -and
                -not $QueryParams.ContainsKey('member_ids') -and
                -not $QueryParams.ContainsKey('bucket_names')
            }
        }

        It 'still throws when -BucketId is used alone, since names cannot be inferred from an ID' {
            { Update-PfbBucketAuditFilter -BucketId 'pslivetest-bucket-id-a' -Array $script:fakeArray -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*-Name is required*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'no longer publishes FilterNames' {
            (Get-Command Update-PfbBucketAuditFilter).Parameters.Keys | Should -Not -Contain 'FilterNames'
        }
    }

    # An empty array must never reach the wire as a dropped selector. All three
    # cmdlets below carry a parameter that satisfies a `required: true` query key
    # (`names`), so binding `@()` or `@('')` must be rejected outright rather than
    # producing a request with the required key missing or blank -- which would
    # silently reconstruct the dead-selector defect this task removes.
    Context 'Task 1b/4 -- required selectors reject an empty array' {
        $script:emptyRequiredCases = @(
            @{ Cmdlet = 'Update-PfbBucketAuditFilter';   Parameter = 'Name'
               Extra = @{ BucketName = 'pslivetest-bucket-a' } }
            @{ Cmdlet = 'New-PfbBucketAccessPolicyRule'; Parameter = 'Name'
               Extra = @{ BucketName = 'pslivetest-bucket-a'; PolicyName = 'pslivetest-policy-a'
                          Attributes = @{ actions = @('s3:GetObject') } } }
            @{ Cmdlet = 'New-PfbBucketAccessPolicyRule'; Parameter = 'BucketName'
               Extra = @{ PolicyName = 'pslivetest-policy-a'; Name = 'pslivetest-rule-a'
                          Attributes = @{ actions = @('s3:GetObject') } } }
            @{ Cmdlet = 'New-PfbBucketAccessPolicyRule'; Parameter = 'PolicyName'
               Extra = @{ BucketName = 'pslivetest-bucket-a'; Name = 'pslivetest-rule-a'
                          Attributes = @{ actions = @('s3:GetObject') } } }
            @{ Cmdlet = 'New-PfbBucketCorsPolicyRule';   Parameter = 'Name'
               Extra = @{ BucketName = 'pslivetest-bucket-a'; PolicyName = 'pslivetest-policy-a'
                          Attributes = @{ allowed_origins = @('*') } } }
            @{ Cmdlet = 'New-PfbBucketCorsPolicyRule';   Parameter = 'BucketName'
               Extra = @{ PolicyName = 'pslivetest-policy-a'; Name = 'pslivetest-rule-a'
                          Attributes = @{ allowed_origins = @('*') } } }
            @{ Cmdlet = 'New-PfbBucketCorsPolicyRule';   Parameter = 'PolicyName'
               Extra = @{ BucketName = 'pslivetest-bucket-a'; Name = 'pslivetest-rule-a'
                          Attributes = @{ allowed_origins = @('*') } } }
        )

        It '<Cmdlet> rejects -<Parameter> @() instead of sending the request' -ForEach $script:emptyRequiredCases {
            $splat = @{ Array = $script:fakeArray; Confirm = $false; ErrorAction = 'Stop' }
            foreach ($k in $Extra.Keys) { $splat[$k] = $Extra[$k] }
            $splat[$Parameter] = @()

            { & $Cmdlet @splat } | Should -Throw

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It '<Cmdlet> rejects -<Parameter> @('''') instead of sending the request' -ForEach $script:emptyRequiredCases {
            $splat = @{ Array = $script:fakeArray; Confirm = $false; ErrorAction = 'Stop' }
            foreach ($k in $Extra.Keys) { $splat[$k] = $Extra[$k] }
            $splat[$Parameter] = @('')

            { & $Cmdlet @splat } | Should -Throw

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }

    Context 'Task 1b -- dead generic Id on the four bucket Get-* cmdlets' {
        It '<Cmdlet> no longer declares an Id parameter' -ForEach $script:deadIdCases {
            (Get-Command $Cmdlet).Parameters.Keys | Should -Not -Contain 'Id'
        }

        It '<Cmdlet> rejects -Id at bind time' -ForEach $script:deadIdCases {
            { & $Cmdlet -Id 'pslivetest-id-a' -Array $script:fakeArray -ErrorAction Stop } | Should -Throw
        }

        It '<Cmdlet> leaves no ById parameter set behind' -ForEach $script:deadIdCases {
            (Get-Command $Cmdlet).ParameterSets.Name | Should -Not -Contain 'ById'
        }

        It '<Cmdlet> emits exactly names for -Name and never ids' -ForEach $script:deadIdCases {
            $expectedEndpoint = $Endpoint
            $expectedMethod   = $Method
            $expectedNames    = 'pslivetest-selector-a'

            & $Cmdlet -Name $expectedNames -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['names'] -eq $expectedNames -and
                -not $QueryParams.ContainsKey('ids')
            }
        }

        It '<Cmdlet> emits no query keys at all for a bare read' -ForEach $script:deadIdCases {
            $expectedEndpoint = $Endpoint
            $expectedMethod   = $Method

            & $Cmdlet -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 0 -and
                -not $QueryParams.ContainsKey('ids')
            }
        }
    }
}
