#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Invariant: every endpoint a shipped cmdlet actually calls must resolve to a key in
# Data/PfbCapabilityMap.json.
#
# WHY THIS TEST BELONGS WITH THE FUSION CONTEXT FEATURE. Before it, a missing map entry was
# merely uninformative: Assert-PfbApiCapability reads a missing entry as
# "if (-not $entry) { return }", so the version gate stays silent. Assert-PfbContextCapability
# does NOT -- it treats "no entry at all" identically to "entry without context_names" (a
# deliberate, documented decision), so with any session context set a cmdlet whose endpoint is
# absent from the map throws BEFORE the wire, claiming the endpoint "does not support the
# context_names parameter". That claim is about context support, for an endpoint the module has
# no entry for at all. This feature is what makes a map gap fatal, so this feature owes the
# invariant that catches the next one.
#
# Discovery is by AST parse, not regex over text, and hardcodes no file and no line: a cmdlet
# added ahead of a map regeneration, a renamed upstream path, or a typo must red this test
# without anyone editing it.

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force

    $script:PublicRoot = (Resolve-Path "$PSScriptRoot/../Public").Path

    # Every (Method, Endpoint) literal pair passed to Invoke-PfbApiRequest anywhere under
    # Public/. Only STRING LITERAL arguments are collected -- a computed endpoint cannot be
    # resolved statically, and silently treating one as absent would be a false failure.
    $script:CallSites = @()

    foreach ($file in (Get-ChildItem -LiteralPath $script:PublicRoot -Filter '*.ps1' -Recurse -File)) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName, [ref]$tokens, [ref]$errors)
        if (-not $ast) { continue }

        $calls = $ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -eq 'Invoke-PfbApiRequest'
        }, $true)

        foreach ($call in $calls) {
            $values = @{}
            $elements = @($call.CommandElements)
            for ($i = 0; $i -lt $elements.Count - 1; $i++) {
                $el = $elements[$i]
                if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                if ($el.ParameterName -notin @('Method', 'Endpoint')) { continue }
                # A parameter written as -Endpoint:'x' carries its value on the parameter node
                # itself rather than as the next element; handle both so neither form is missed.
                $arg = if ($null -ne $el.Argument) { $el.Argument } else { $elements[$i + 1] }
                if ($arg -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $values[$el.ParameterName] = $arg.Value
                }
            }
            if (-not ($values.ContainsKey('Method') -and $values.ContainsKey('Endpoint'))) { continue }

            $script:CallSites += [PSCustomObject]@{
                File     = $file.FullName.Substring($script:PublicRoot.Length).TrimStart('\', '/')
                Line     = $call.Extent.StartLineNumber
                Method   = $values['Method']
                Endpoint = $values['Endpoint']
            }
        }
    }
}

Describe 'Public cmdlet endpoints resolve to capability-map keys' {

    It 'finds the Invoke-PfbApiRequest call sites (a silent no-match scan would assert nothing)' {
        # Mandatory guard: without it, a scanner that matched nothing would pass forever and
        # this whole file would be inert. The module resolved 534 distinct (method, endpoint)
        # keys at the time of writing, so the floor is set well below that but far above zero --
        # a wildly smaller number means the discovery broke, not that the codebase shrank.
        @($script:CallSites).Count | Should -BeGreaterThan 0
        @($script:CallSites | ForEach-Object { '{0} {1}' -f $_.Method, $_.Endpoint } | Sort-Object -Unique).Count |
            Should -BeGreaterThan 400 -Because 'the AST scan must reach the whole Public/ surface, not a corner of it'
    }

    It 'has exactly two endpoints absent from the capability map, both owned by issue #80' {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ Sites = $script:CallSites } {
            param($Sites)

            $map = Get-PfbCapabilityMap
            $mapKeys = @($map.endpoints.PSObject.Properties.Name)
            @($mapKeys).Count | Should -BeGreaterThan 0 -Because 'the shipped map must actually load'

            # Keys are built the ONE sanctioned way. Never re-implement this normalisation: a
            # copy differing by a leading slash or by case would miss every entry in the map,
            # and the miss is silent -- see Get-PfbEndpointKey's header.
            $unresolved = @(
                $Sites |
                    ForEach-Object { Get-PfbEndpointKey -Method $_.Method -Endpoint $_.Endpoint } |
                    Sort-Object -Unique |
                    Where-Object { $mapKeys -notcontains $_ }
            )

            # EXACT-MATCH expected set, not a pattern and not a subset assertion, so a third gap
            # cannot hide behind it. Both entries are known and both retire TOGETHER with
            # issue #80 ("Update-PfbSmtp targets a nonexistent 2.x path; consolidate the SMTP
            # cmdlets onto /smtp-servers"):
            #
            #   GET /smtp   -- Get-PfbSmtp pins -ApiVersionOverride '1.12', so this is a working
            #                 REST 1.x call. Its absence from the map is correct BY
            #                 CONSTRUCTION: the map is generated from the 2.0-2.28 specs, so no
            #                 1.x path can ever appear in it. This is the module's entire 1.x
            #                 surface -- one cmdlet, not a family -- and #80 replaces it with an
            #                 alias for Get-PfbSmtpServer.
            #   PATCH /smtp -- Update-PfbSmtp passes no override, so it resolves against the
            #                 negotiated 2.x, where /smtp does not exist. It has never worked:
            #                 the GET was ported to 1.12 and the PATCH was not. #80 retires it.
            #
            # Deliberately self-retiring: this assertion is a tripwire in BOTH directions.
            $expected = @('GET /smtp', 'PATCH /smtp')

            $detail = if ($unresolved.Count) { $unresolved -join ', ' } else { '(none)' }
            $unresolved -join ',' | Should -Be ($expected -join ',') -Because (
                "found: $detail. If a NEW endpoint appears here, either the cmdlet's path is " +
                'wrong or the capability map needs regenerating -- do not widen this list to ' +
                'silence it. If the list is now EMPTY, issue #80 has landed and the SMTP ' +
                'cmdlets are consolidated onto /smtp-servers: DELETE the expected set and this ' +
                'comment rather than updating them.')
        }
    }
}
