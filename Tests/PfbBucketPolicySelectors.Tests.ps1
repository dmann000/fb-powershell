#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

$script:selectorCases = @(
    @{ Cmdlet = 'Get-PfbBucketAuditFilter';       NameKey = 'names';        BucketKey = 'bucket_names'; Endpoint = 'buckets/audit-filters'; Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicy';        NameKey = 'names';        BucketKey = 'bucket_names'; Endpoint = 'buckets/cross-origin-resource-sharing-policies'; Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketAccessPolicy';      NameKey = 'names';        BucketKey = 'bucket_names'; Endpoint = 'buckets/bucket-access-policies'; Method = 'GET' }
    @{ Cmdlet = 'Remove-PfbBucketAuditFilter';    NameKey = 'names';        BucketKey = 'bucket_names'; Endpoint = 'buckets/audit-filters'; Method = 'DELETE' }
    @{ Cmdlet = 'Remove-PfbBucketCorsPolicy';     NameKey = 'names';        BucketKey = 'bucket_names'; Endpoint = 'buckets/cross-origin-resource-sharing-policies'; Method = 'DELETE' }
    @{ Cmdlet = 'Get-PfbBucketAccessPolicyRule';  NameKey = 'policy_names'; BucketKey = 'bucket_names'; Endpoint = 'buckets/bucket-access-policies/rules'; Method = 'GET' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicyRule';    NameKey = 'policy_names'; BucketKey = 'bucket_names'; Endpoint = 'buckets/cross-origin-resource-sharing-policies/rules'; Method = 'GET' }
    @{ Cmdlet = 'New-PfbBucketAuditFilter';       NameKey = 'names';        BucketKey = 'bucket_names'; Endpoint = 'buckets/audit-filters'; Method = 'POST' }
)

$script:ruleCases = @(
    @{ Cmdlet = 'Get-PfbBucketAccessPolicyRule'; Endpoint = 'buckets/bucket-access-policies/rules' }
    @{ Cmdlet = 'Get-PfbBucketCorsPolicyRule';   Endpoint = 'buckets/cross-origin-resource-sharing-policies/rules' }
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

    It '<Cmdlet> removes MemberName and publishes BucketName' -ForEach $script:selectorCases {
        $keys = (Get-Command $Cmdlet).Parameters.Keys
        $keys | Should -Not -Contain 'MemberName'
        $keys | Should -Contain 'BucketName'
    }

    It '<Cmdlet> maps Name to <NameKey> with exact endpoint, method, and no member_names' -ForEach $script:selectorCases {
        $parameters = @{ Name = 'pslivetest-selector-a'; Array = $script:fakeArray }
        if ($Cmdlet -like '*PolicyRule') { $parameters['PolicyName'] = 'pslivetest-selector-a'; $parameters.Remove('Name') }
        if ($Cmdlet -like 'Remove-*') { $parameters['Confirm'] = $false }
        if ($Cmdlet -eq 'New-PfbBucketAuditFilter') { $parameters['Attributes'] = @{ actions = @('s3.GetObject') } }
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

    It '<Cmdlet> maps BucketName to bucket_names with exact endpoint, method, and no member_names' -ForEach $script:selectorCases {
        $parameters = @{ BucketName = 'pslivetest-bucket-a'; Array = $script:fakeArray }
        if ($Cmdlet -like 'Remove-*') { $parameters['Confirm'] = $false }
        if ($Cmdlet -eq 'New-PfbBucketAuditFilter') { $parameters['Attributes'] = @{ actions = @('s3.GetObject') } }
        & $Cmdlet @parameters

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams.Count -eq 1 -and $QueryParams[$BucketKey] -eq 'pslivetest-bucket-a' -and
            -not $QueryParams.ContainsKey('member_names')
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
