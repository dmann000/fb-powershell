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
)

# Pipeline binding: a bare piped string must mean "bucket" on the destructive
# cmdlets exactly as it does on their Get-* siblings.
$script:pipelineCases = @(
    @{ Cmdlet = 'Get-PfbBucketAuditFilter';    Endpoint = 'buckets/audit-filters'; Method = 'GET' }
    @{ Cmdlet = 'Remove-PfbBucketAuditFilter'; Endpoint = 'buckets/audit-filters'; Method = 'DELETE' }
    @{ Cmdlet = 'Remove-PfbBucketCorsPolicy';  Endpoint = 'buckets/cross-origin-resource-sharing-policies'; Method = 'DELETE' }
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
}
