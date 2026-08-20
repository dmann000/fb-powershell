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
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

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

            # EXACT-MATCH expected set, empty: EVERY endpoint literal in Public/ must resolve to
            # a capability-map key. No allowlist, so a gap cannot hide behind one.
            #
            # This started life carrying two entries, GET /smtp and PATCH /smtp, as a deliberately
            # self-retiring tripwire against issue #80. #80 landed in PR #108 and the tripwire
            # fired exactly as designed: Get-PfbSmtp and Update-PfbSmtp are gone, consolidated
            # onto /smtp-servers, and the module now has no REST 1.x surface at all
            # (zero -ApiVersionOverride sites). The set was DELETED rather than updated, per its
            # own instruction. Tests/RemovedCmdlets.Tests.ps1 guards the removal itself.
            #
            # Do not reintroduce an allowlist to silence a failure here. A new entry means either
            # a cmdlet's endpoint path is wrong or the capability map needs regenerating.
            $expected = @()

            $detail = if ($unresolved.Count) { $unresolved -join ', ' } else { '(none)' }
            $unresolved -join ',' | Should -Be ($expected -join ',') -Because (
                "found: $detail. Either the cmdlet's endpoint path is wrong or the capability " +
                'map needs regenerating -- do not widen this list to silence it.')
        }
    }
}
