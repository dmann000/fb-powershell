#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force

    # Source path used by the declaration tests below. The three context properties live in a
    # [PSCustomObject]@{} literal that only a real connect could produce, so the presence of
    # the state is asserted against the source rather than against a live array.
    $script:ConnectSourcePath = Join-Path $PSScriptRoot '../Public/Connection/Connect-PfbArray.ps1'
}

Describe 'connection context state' {
    It 'copies without mutating the original and preserves the type name' {
        InModuleScope PureStorageFlashBladePowerShell {
            $fake = [PSCustomObject]@{
                PSTypeName         = 'PureStorage.FlashBlade.Connection'
                Endpoint           = 'fb.example'
                ApiVersion         = '2.26'
                DefaultContext     = $null
                ContextOverride    = $null
                AuthorizationModel = $null
            }
            $copy = Copy-PfbConnection -Array $fake
            $copy.DefaultContext = New-PfbContext -Entries @((New-PfbContextEntry -Name 'FB-B'))
            $fake.DefaultContext | Should -BeNullOrEmpty
            $copy.PSObject.TypeNames | Should -Contain 'PureStorage.FlashBlade.Connection'
            [object]::ReferenceEquals($copy, $fake) | Should -BeFalse
        }
    }

    It 'repoints both caches at the copy' {
        InModuleScope PureStorageFlashBladePowerShell {
            $fake = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint   = 'fb.example'
                ApiVersion = '2.26'
            }
            $originalArrays = $script:PfbArrays
            $originalDefault = $script:PfbDefaultArray
            try {
                $script:PfbArrays = @{ 'fb.example' = $fake }
                $script:PfbDefaultArray = $fake
                $copy = Copy-PfbConnection -Array $fake
                Update-PfbConnectionCache -Array $copy
                [object]::ReferenceEquals($script:PfbArrays['fb.example'], $copy) | Should -BeTrue
                [object]::ReferenceEquals($script:PfbDefaultArray, $copy) | Should -BeTrue
            }
            finally {
                # param()-passed restore: .GetNewClosure() against a module scope fails under
                # StrictMode and silently leaks state.
                & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $originalArrays $originalDefault
            }
        }
    }

    It 'leaves a different endpoint in the cache alone' {
        InModuleScope PureStorageFlashBladePowerShell {
            $fake = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint   = 'fb.example'
                ApiVersion = '2.26'
            }
            $originalArrays = $script:PfbArrays
            $originalDefault = $script:PfbDefaultArray
            try {
                $other = [PSCustomObject]@{ PSTypeName = 'PureStorage.FlashBlade.Connection'; Endpoint = 'other.example' }
                $script:PfbArrays = @{ 'other.example' = $other }
                $script:PfbDefaultArray = $other
                Update-PfbConnectionCache -Array (Copy-PfbConnection -Array $fake)
                [object]::ReferenceEquals($script:PfbDefaultArray, $other) | Should -BeTrue
                $script:PfbArrays.ContainsKey('fb.example') | Should -BeFalse
            }
            finally {
                & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $originalArrays $originalDefault
            }
        }
    }

    It 'does not repoint any cache from Copy-PfbConnection itself' {
        InModuleScope PureStorageFlashBladePowerShell {
            $fake = [PSCustomObject]@{
                PSTypeName = 'PureStorage.FlashBlade.Connection'
                Endpoint   = 'fb.example'
                ApiVersion = '2.26'
            }
            $originalArrays = $script:PfbArrays
            $originalDefault = $script:PfbDefaultArray
            try {
                $script:PfbArrays = @{ 'fb.example' = $fake }
                $script:PfbDefaultArray = $fake
                $copy = Copy-PfbConnection -Array $fake
                [object]::ReferenceEquals($script:PfbArrays['fb.example'], $fake) | Should -BeTrue
                [object]::ReferenceEquals($script:PfbDefaultArray, $fake) | Should -BeTrue
                $copy | Should -Not -BeNullOrEmpty
            }
            finally {
                & { param($a, $d) $script:PfbArrays = $a; $script:PfbDefaultArray = $d } $originalArrays $originalDefault
            }
        }
    }
}

Describe 'Connect-PfbArray context properties' {
    It 'declares the three context parameters' {
        $cmd = Get-Command Connect-PfbArray
        foreach ($p in 'Context', 'Kind', 'AllArrays') { $cmd.Parameters.Keys | Should -Contain $p }
    }

    It 'constrains -Kind to the three valid context kinds' {
        $cmd = Get-Command Connect-PfbArray
        $validate = $cmd.Parameters['Kind'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validate | Should -Not -BeNullOrEmpty
        $validate.ValidValues | Should -Be @('Array', 'Fleet', 'TopologyGroup')
    }

    It 'initializes the three context state properties on the connection object' {
        $source = Get-Content -Path $script:ConnectSourcePath -Raw
        foreach ($prop in 'DefaultContext', 'ContextOverride', 'AuthorizationModel') {
            $source | Should -Match "(?m)^\s+$prop\s+=\s+\`$null\s*$"
        }
    }
}
