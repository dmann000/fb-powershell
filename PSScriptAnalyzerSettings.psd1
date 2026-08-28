@{
    # PSScriptAnalyzer settings for PureStorageFlashBladePowerShell.
    #
    # Every count below was measured by pssa-tasks\New-PfbPssaSettings.ps1 at the moment
    # this file was generated, so each is reproducible against a known tree:
    #     2026-08-28, commit 03ea602, PSScriptAnalyzer 1.25.0
    # The sweep covers Public/, Private/,
    # Tests/, tools/, scripts/ AND the repo root (the root matters: the .psd1/.psm1 live
    # there, and a five-directory sweep silently never analyses them, which makes four
    # manifest/module rules -- including the preset's own PSMissingModuleManifestField --
    # unable to fire at all).

    IncludeRules = @(
        # --- the PSGallery preset verbatim, because publication is the goal.
        # Kept complete even where it costs signal. PSUseSingularNouns produces
        #     44 findings -- 29 internal helpers, 15 exported cmdlets
        # and stays in, because a file claiming to target the preset should not quietly
        # diverge from it. They are documented in
        # PSScriptAnalyzer-baseline-2026-08-26.md, which is the
        # "compelling reason ... add that information to your documentation" the
        # Gallery guidelines ask for.
        'PSUseApprovedVerbs', 'PSReservedCmdletChar', 'PSReservedParams',
        'PSShouldProcess', 'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns', 'PSMissingModuleManifestField',
        'PSAvoidDefaultValueSwitchParameter', 'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingWMICmdlet', 'PSAvoidUsingEmptyCatchBlock',
        'PSUseCmdletCorrectly', 'PSAvoidUsingPositionalParameters',
        'PSAvoidGlobalVars', 'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidUsingInvokeExpression', 'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingComputerNameHardcoded', 'PSUsePSCredentialType', 'PSDSC*',

        # --- not in the preset, but each caught something real in this repo
        'PSUseBOMForUnicodeEncodedFile',         # the BOM-less non-ASCII defect: such a
                                                 # file decodes as UTF-8 on pwsh 7 and
                                                 # Windows-1252 on 5.1, so Get-Help
                                                 # renders mojibake on 5.1 only
        'PSAvoidAssignmentToAutomaticVariable',  # assignment to $matches

        # --- not in the preset, at ZERO repo-wide, adopted as a regression guard.
        # Configured below; without that configuration it finds nothing and reports a
        # vacuous zero rather than an error.
        'PSUseCompatibleSyntax'

        # PSUseCompatibleCommands is NOT listed, and this is a correction to an earlier
        # draft that adopted it as a second guard on a measured "zero". That zero was
        # scope-limited. Repo-wide it is 21889:
        #     Public/ 0   Private/ 2   Tests/ 21870   tools/ 14   scripts/ 3   root 0
        # Tests/ dominates because the rule compares against profiles of BUILT-IN
        # commands only, so every Pester assertion is reported -- "The parameter 'Throw'
        # is not available for command 'Should'". Private/'s 2 are ConvertFrom-Json
        # -Depth, both already inside an `if ($PSVersionTable.PSVersion.Major -ge 6)`
        # guard: the rule reads neither version guards nor #Requires, the same
        # guard-blindness that makes PSUseCompatibleTypes unusable here.
        # Only Public/ is genuinely clean, so it is gated there like T11 -- see below.

        # PSProvideCommentHelp is deliberately NOT listed here. It is configured below
        # but only ever requested explicitly by the CI step, scoped to Public/.
        # Listing it would add 133 Information findings to every ordinary run.
        #
        # A caller's -IncludeRule is UNION'd with this allowlist -- measured, and NOT
        # the override an earlier draft recorded. So the CI step must filter its results
        # by RuleName: with this file, `-IncludeRule PSProvideCommentHelp` over Public/
        # returns 22 records, none of them PSProvideCommentHelp, and a naive
        # `.Count -gt 0` gate fails on unrelated preset findings.
        # ExcludeRules is the asymmetric one: it VETOES a caller's -IncludeRule. So
        # excluding this rule here, rather than merely not listing it, would break the
        # gate outright.
    )

    Rules = @{
        # Gate for Public/ only. ExportedOnly = $true -- the DEFAULT -- makes this rule
        # inert in this codebase: one function per dot-sourced file, exports declared in
        # the manifest, so no analysed file holds its own export statement and the rule
        # reports 0 across all 544 cmdlets WITHOUT EVALUATING ANY OF THEM.
        # With ExportedOnly = $false, tools/ counted with tools/lib/:
        #     Public/ 0   Private/ 12   Tests/ 102   tools/ 17   scripts/ 2   root 0
        # Public/ being 0 is the real finding -- every exported cmdlet is
        # documented -- and that is what CI holds. Severity is Information, so the CI
        # step must name the rule; a severity threshold would never see it.
        PSProvideCommentHelp = @{
            Enable       = $true
            ExportedOnly = $false
        }

        # TargetVersions / TargetProfiles are REQUIRED, not tuning. Without them these
        # two rules evaluate nothing and return 0. Control-verified 2026-08-28.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        # Configured but NOT in IncludeRules, for the reason recorded above. CI requests
        # it explicitly and scoped to Public/, where it is genuinely 0.
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @(
                'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework',
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
            )
        }
    }

    # =====================================================================
    # T10 -- the ten default-disabled rules stay OFF. Recorded, not omitted.
    # =====================================================================
    #
    # These are disabled by default in PSScriptAnalyzer and are NOT enabled here. Their
    # counts are written down so their absence reads as a decision rather than an
    # oversight, and so nobody enables one without knowing the size of the sweep it
    # implies. Force-enable sweep, 2026-08-28, all five directories plus the
    # root, each rule enabled on its own (PSAvoidLongLines at its 120-column default,
    # without which it measures nothing):
    #
    #     PSUseConstrainedLanguageMode                   4825
    #     PSAvoidLongLines                               3614
    #     PSUseConsistentWhitespace                      3419
    #     PSUseConsistentIndentation                      980
    #     PSAlignAssignmentStatement                      503
    #     PSPlaceCloseBrace                               180
    #     PSAvoidUsingDoubleQuotesForConstantString       106
    #     PSUseConsistentParameterSetName                  93
    #     PSUseConsistentParametersKind                    54
    #     PSUseCorrectCasing                               52
    #                                                  ------
    #                                                   13826
    #
    # PSUseConstrainedLanguageMode is the one to be careful about: it is not a style
    # rule, and its 4825 findings are not formatting debt. It reports constructs that
    # would fail under Constrained Language Mode. This module is not supported under CLM
    # and does not claim to be, so the rule is off -- but enabling it "to tidy up" would
    # be a functional change, not a cosmetic one.
    #
    # ALSO NOT ADOPTED, and for a different reason: PSUseCompatibleTypes. It is at
    # 30, not 0. All were verified false positives -- each flagged member was
    # executed on both 5.1 and 7 -- because it reads neither $PSVersionTable guards nor
    # #Requires, so a type used only inside a correctly-guarded branch is still
    # reported. It must not be adopted on a mistaken "it's already clean" reading.
    #
    # Rules deliberately left out of IncludeRules, with counts and reasons:
    #     PSReviewUnusedParameter                  62   ArgumentCompleter scriptblocks must take
    #                                                   the full signature even when only
    #                                                   $WordToComplete is used; also fires on
    #                                                   Pester scriptblock params it cannot see
    #                                                   through
    #     PSAvoidUsingWriteHost                    94   the flagged files are CLI scripts and
    #                                                   build tools whose job is console output
    #     PSUseOutputTypeCorrectly                108   Information-only polish across
    #                                                   544 cmdlets; no correctness content
    #     PSUseProcessBlockForPipelineCommand      31   test helpers are not pipeline cmdlets
    #     PSAvoidUsingConvertToSecureStringWithPlainText
    #                                              21   test fixtures only, and SUPPRESSED at the
    #                                                   sites (T9) rather than switched off
    #                                                   globally -- so it still fires for Public/
    #                                                   and Private/, where it would be real.
    #                                                   The count is suppressed SITES, not live
    #                                                   findings
}