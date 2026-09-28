@{
    # Every pattern and suppression in the local ps51-compat-check.mjs hook, enumerated at
    # port time. Tests/Test-PfbPs51Compat.Tests.ps1 fails if any id here has no case.
    HookConstructs = @(
        'c1-null-coalesce', 'c1-null-coalesce-assign', 'c1-null-conditional-member', 'c1-null-conditional-index',
        'c1-chain-and', 'c1-chain-or', 'c1-ternary-paren', 'c1-ternary-var', 'c1-other-parse-error',
        'c2-convertfrom-json-depth', 'c2-convertfrom-json-ashashtable', 'c2-foreach-parallel', 'c2-foreach-throttlelimit',
        'c2-content-asbytestream', 'c2-test-json', 'c2-join-string', 'c2-split-path-leafbase', 'c2-skipcertificatecheck',
        'c2-encoding-utf8nobom', 'c2-psstyle', 'c3-sort-object-culture', 'c3-utf8-bom-write', 'c3-is-platform-variable',
        's-pragma', 's-version-gate', 's-skipped-block', 's-all-describes-skipped', 's-strip-inert', 's-not-in-tests',
        's-requires-7', 's-out-of-scope', 's-convertto-anchoring'
    )
    # Shapes on which the hook and the script are KNOWN to disagree. None has a fixture, and
    # the parity run treats a disagreement of exactly one of these shapes as expected.
    KnownDivergences = @(
        # Hook quirks: the hook flags, the script may not.
        'A version gate on the finding''s own line: the hook looks only at the 6 lines BEFORE it (ps51-compat-check.mjs, the LOOKBACK loop in suppressed()).'
        'A finding after a Describe block closes: the hook walks back to the nearest opener line, not the enclosing block (ps51-compat-check.mjs, inSkippedBlock()).'
        # The script is stricter: the hook is silent, the script reports.
        'The % alias of ForEach-Object (-Parallel, -ThrottleLimit): the hook''s \b(?:ForEach-Object|%)\b cannot match a % between spaces, so the hook never flags it. The script is stricter.'
        'A variable or subexpression inside an expandable string ("$PSStyle", "$(Split-Path x -LeafBase)"): the hook blanks the whole double-quoted string, the AST sees the nested expression. The script is stricter.'
        'A quoted -Encoding value (-Encoding ''utf8NoBOM'', -Encoding ''UTF8''): the hook blanks the quoted value before its quote group is tried, the AST reads the constant. The script is stricter.'
        'A 5.1 parse error that matches none of the hook''s RE_CLASS1 patterns (an unbalanced brace, say): ps51-compat-check.mjs calls the 5.1 parser only after an RE_CLASS1 match (scanFile(), :307), so it never adjudicates one, and ps-parse-check.mjs reports it only if PowerShell 7 fails to parse it too. The script parses every in-scope file under 5.1 and reports it. The script is stricter.'
    )
    # One case per construct. FlagsPath and SuppressedPath are the repo-relative paths at
    # which the test materializes each sample, which is what decides its scope. A case whose
    # suppressed sample is valid 5.1 syntax, with no hook suppression involved, has
    # Suppression = $null. The s-* ids are covered through Suppression, except
    # s-skipped-block and s-all-describes-skipped, which are cases of their own.
    Cases = @(
        # ---- class 1: the 5.1 parser's verdict ----------------------------------------
        @{
            Id = 'c1-null-coalesce'; Construct = 'c1-null-coalesce'; Rule = 'c1-parse'; Class = 1
            FlagsFile = 'c1-null-coalesce.flags.txt'; FlagsPath = 'Tests/X.Tests.ps1'
            SuppressedFile = 'c1-null-coalesce.suppressed.txt'; SuppressedPath = 'Tests/X.Tests.ps1'
            Suppression = 's-strip-inert'
        }
        @{
            Id = 'c1-null-coalesce-assign'; Construct = 'c1-null-coalesce-assign'; Rule = 'c1-parse'; Class = 1
            FlagsFile = 'c1-null-coalesce-assign.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c1-null-coalesce-assign.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-strip-inert'
        }
        @{
            # Suppressed sample: $x?.Name is valid 5.1, a variable named x? (measured).
            Id = 'c1-null-conditional-member'; Construct = 'c1-null-conditional-member'; Rule = 'c1-parse'; Class = 1
            FlagsFile = 'c1-null-conditional-member.flags.txt'; FlagsPath = 'scripts/X.ps1'
            SuppressedFile = 'c1-null-conditional-member.suppressed.txt'; SuppressedPath = 'scripts/X.ps1'
            Suppression = $null
        }
        @{
            # Suppressed sample: $x?[0] is valid 5.1, a variable named x? (measured).
            Id = 'c1-null-conditional-index'; Construct = 'c1-null-conditional-index'; Rule = 'c1-parse'; Class = 1
            FlagsFile = 'c1-null-conditional-index.flags.txt'; FlagsPath = 'Private/X.ps1'
            SuppressedFile = 'c1-null-conditional-index.suppressed.txt'; SuppressedPath = 'Private/X.ps1'
            Suppression = $null
        }
        @{
            Id = 'c1-chain-and'; Construct = 'c1-chain-and'; Rule = 'c1-parse'; Class = 1
            FlagsFile = 'c1-chain-and.flags.txt'; FlagsPath = 'Tests/X.Tests.ps1'
            SuppressedFile = 'c1-chain-and.suppressed.txt'; SuppressedPath = 'Tests/X.Tests.ps1'
            Suppression = 's-strip-inert'
        }
        @{
            Id = 'c1-chain-or'; Construct = 'c1-chain-or'; Rule = 'c1-parse'; Class = 1
            FlagsFile = 'c1-chain-or.flags.txt'; FlagsPath = 'PureStorageFlashBladePowerShell.psm1'
            SuppressedFile = 'c1-chain-or.suppressed.txt'; SuppressedPath = 'PureStorageFlashBladePowerShell.psm1'
            Suppression = 's-requires-7'
        }
        @{
            Id = 'c1-ternary-paren'; Construct = 'c1-ternary-paren'; Rule = 'c1-parse'; Class = 1
            FlagsFile = 'c1-ternary-paren.flags.txt'; FlagsPath = 'Tests/X.Tests.ps1'
            SuppressedFile = 'c1-ternary-paren.suppressed.txt'; SuppressedPath = 'tools/X.ps1'
            Suppression = 's-out-of-scope'
        }
        @{
            Id = 'c1-ternary-var'; Construct = 'c1-ternary-var'; Rule = 'c1-parse'; Class = 1
            FlagsFile = 'c1-ternary-var.flags.txt'; FlagsPath = 'tools/lib/X.ps1'
            SuppressedFile = 'c1-ternary-var.suppressed.txt'; SuppressedPath = 'tools/lib/X.ps1'
            Suppression = 's-strip-inert'
        }
        @{
            Id = 'c1-other-parse-error'; Construct = 'c1-other-parse-error'; Rule = 'c1-parse'; Class = 1
            FlagsFile = 'c1-other-parse-error.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c1-other-parse-error.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = $null
        }

        # ---- class 2: valid 5.1 syntax that throws at runtime -------------------------
        @{
            Id = 'c2-convertfrom-json-depth'; Construct = 'c2-convertfrom-json-depth'; Rule = 'c2-convertfrom-json-depth'; Class = 2
            FlagsFile = 'c2-convertfrom-json-depth.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-convertfrom-json-depth.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-convertto-anchoring'
        }
        @{
            Id = 'c2-convertfrom-json-ashashtable'; Construct = 'c2-convertfrom-json-ashashtable'; Rule = 'c2-convertfrom-json-ashashtable'; Class = 2
            FlagsFile = 'c2-convertfrom-json-ashashtable.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-convertfrom-json-ashashtable.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-version-gate'
        }
        @{
            Id = 'c2-foreach-parallel'; Construct = 'c2-foreach-parallel'; Rule = 'c2-foreach-parallel'; Class = 2
            FlagsFile = 'c2-foreach-parallel.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-foreach-parallel.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-strip-inert'
        }
        @{
            Id = 'c2-foreach-throttlelimit'; Construct = 'c2-foreach-throttlelimit'; Rule = 'c2-foreach-throttlelimit'; Class = 2
            FlagsFile = 'c2-foreach-throttlelimit.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-foreach-throttlelimit.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-pragma'
        }
        @{
            Id = 'c2-content-asbytestream'; Construct = 'c2-content-asbytestream'; Rule = 'c2-content-asbytestream'; Class = 2
            FlagsFile = 'c2-content-asbytestream.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-content-asbytestream.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-strip-inert'
        }
        @{
            Id = 'c2-test-json'; Construct = 'c2-test-json'; Rule = 'c2-test-json'; Class = 2
            FlagsFile = 'c2-test-json.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-test-json.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-version-gate'
        }
        @{
            Id = 'c2-join-string'; Construct = 'c2-join-string'; Rule = 'c2-join-string'; Class = 2
            FlagsFile = 'c2-join-string.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-join-string.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-pragma'
        }
        @{
            Id = 'c2-split-path-leafbase'; Construct = 'c2-split-path-leafbase'; Rule = 'c2-split-path-leafbase'; Class = 2
            FlagsFile = 'c2-split-path-leafbase.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-split-path-leafbase.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-strip-inert'
        }
        @{
            Id = 'c2-skipcertificatecheck'; Construct = 'c2-skipcertificatecheck'; Rule = 'c2-skipcertificatecheck'; Class = 2
            FlagsFile = 'c2-skipcertificatecheck.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-skipcertificatecheck.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-version-gate'
        }
        @{
            # Suppressed sample: classes 2 and 3 cover only what ships, so an undeclared
            # Tests/ file is out of their scope.
            Id = 'c2-encoding-utf8nobom'; Construct = 'c2-encoding-utf8nobom'; Rule = 'c2-encoding-utf8nobom'; Class = 2
            FlagsFile = 'c2-encoding-utf8nobom.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-encoding-utf8nobom.suppressed.txt'; SuppressedPath = 'Tests/X.Tests.ps1'
            Suppression = 's-out-of-scope'
        }
        @{
            Id = 'c2-psstyle'; Construct = 'c2-psstyle'; Rule = 'c2-psstyle'; Class = 2
            FlagsFile = 'c2-psstyle.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c2-psstyle.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-strip-inert'
        }

        # ---- class 3: no failure on 5.1, different behaviour --------------------------
        @{
            Id = 'c3-sort-object-culture'; Construct = 'c3-sort-object-culture'; Rule = 'c3-sort-object-culture'; Class = 3
            FlagsFile = 'c3-sort-object-culture.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c3-sort-object-culture.suppressed.txt'; SuppressedPath = 'Public/X.ps1'
            Suppression = 's-pragma'
        }
        @{
            # Suppressed sample: a Tests/ helper declaring 5.1, the shape of
            # Tests/PfbTestModule.ps1. In scope by the declaration, exempt as a test file.
            Id = 'c3-utf8-bom-write'; Construct = 'c3-utf8-bom-write'; Rule = 'c3-utf8-bom-write'; Class = 3
            FlagsFile = 'c3-utf8-bom-write.flags.txt'; FlagsPath = 'Public/X.ps1'
            SuppressedFile = 'c3-utf8-bom-write.suppressed.txt'; SuppressedPath = 'Tests/Helper.ps1'
            Suppression = 's-not-in-tests'
        }
        @{
            Id = 'c3-is-platform-variable'; Construct = 'c3-is-platform-variable'; Rule = 'c3-is-platform-variable'; Class = 3
            FlagsFile = 'c3-is-platform-variable.flags.txt'; FlagsPath = 'Private/X.ps1'
            SuppressedFile = 'c3-is-platform-variable.suppressed.txt'; SuppressedPath = 'Private/X.ps1'
            Suppression = 's-version-gate'
        }

        # ---- suppressions with a case of their own ------------------------------------
        @{
            # The finding sits more than 6 lines below the Describe line, so only the
            # skipped-block walk, not the version-gate lookback, can suppress it.
            Id = 's-skipped-block'; Construct = 's-skipped-block'; Rule = 'c2-convertfrom-json-depth'; Class = 2
            FlagsFile = 's-skipped-block.flags.txt'; FlagsPath = 'Tests/Y.Tests.ps1'
            SuppressedFile = 's-skipped-block.suppressed.txt'; SuppressedPath = 'Tests/Y.Tests.ps1'
            Suppression = 's-skipped-block'
        }
        @{
            # A file-scope BeforeAll: suppressed only while every Describe in the file is
            # skipped on PSVersion. The flags sample adds one unskipped Describe.
            Id = 's-all-describes-skipped'; Construct = 's-all-describes-skipped'; Rule = 'c2-convertfrom-json-depth'; Class = 2
            FlagsFile = 's-all-describes-skipped.flags.txt'; FlagsPath = 'Tests/Z.Tests.ps1'
            SuppressedFile = 's-all-describes-skipped.suppressed.txt'; SuppressedPath = 'Tests/Z.Tests.ps1'
            Suppression = 's-all-describes-skipped'
        }
    )
}
