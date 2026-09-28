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
        # The hook flags, the script does not. In none of these does the script miss a
        # construct that would run on 5.1: each is a hook false positive, code that never runs
        # on 5.1, or a file the script already fails as class 1.
        'A finding inside a PSVersion-skipped Describe but after a nested, unskipped Context closes, or below a line that merely starts with the word Describe or Context (a hashtable key `Context = 1`): the hook''s inSkippedBlock() walks back to the nearest line matching RE_BLOCK_OPEN and reads that line''s guard; the script reads the guard of the enclosing Describe/Context CommandAst, which is skipped.'
        'A Describe/Context opener wrapped over more than 3 lines, with its -Skip:(...PSVersion...) on the 4th line or later: the hook''s inSkippedBlock() joins only 3 lines (slice(k, k + 3)) before testing RE_SKIP_GUARD; the script reads the whole CommandAst.'
        'A command name that appears but is not the command invoked -- mentioned (Get-Command Test-Json, Join-String as a bareword argument), defined (a polyfill `function Test-Json { }`), or inside a longer hyphenated name (Invoke-Test-Json): the hook''s \b-anchored PATTERNS regexes match the name alone in stripInert text; the script matches only the name a CommandAst invokes.'
        'A parameter of a NESTED command on the anchored command''s line (ConvertFrom-Json -InputObject (ConvertTo-Json $x -Depth 5)): the hook''s ARG run of non-space tokens crosses into the parentheses and credits -Depth to ConvertFrom-Json, a hook false positive; the script reads each CommandAst''s own parameters.'
        'A class 2/3 construct in a file that does not parse on 5.1: the hook''s scanFile() runs PATTERNS whatever the parse outcome; the script reports the class-1 parse error (exit 1) and does not run classes 2/3 on an AST the parser rejected, so the construct surfaces once the file parses.'
        'A here-string content line that is an indented closing quote (a line holding only spaces and ''@): PowerShell ends a here-string only at a closing quote in column 0, but the hook''s stripInert() accepts leading whitespace, ends the string early and scans the rest of its content as code, a hook false positive; the script reads the here-string token.'
        'A command name inside a string delimited by typographic quotes (U+2018/U+2019 or U+201C/U+201D), which PowerShell accepts as quote characters: the hook''s stripInert() blanks only ASCII-quoted strings, so the name matches PATTERNS, a hook false positive; the script''s tokenizer reads a string.'
        # The script is stricter: the hook is silent, the script reports.
        'The % alias of ForEach-Object (-Parallel, -ThrottleLimit): the hook''s \b(?:ForEach-Object|%)\b cannot match a % between spaces, so the hook never flags it. The script is stricter.'
        'A variable or subexpression inside an expandable string ("$PSStyle", "$(Split-Path x -LeafBase)"): the hook blanks the whole double-quoted string, the AST sees the nested expression. The script is stricter.'
        'A quoted -Encoding value (-Encoding ''utf8NoBOM'', -Encoding ''UTF8''): the hook blanks the quoted value before its quote group is tried, the AST reads the constant. The script is stricter.'
        'The colon form of -Encoding (-Encoding:utf8NoBOM, -Encoding:UTF8): the hook''s -Encoding patterns need whitespace after -Encoding (-Encoding\s+); the AST binds the argument in either form. The script is stricter.'
        'A braced variable name (${IsWindows}, ${PSStyle}): the hook''s \$Is(?:Windows|Linux|MacOS|CoreCLR)\b and \$PSStyle\b need the name directly after the $; the AST gives the same VariablePath either way. The script is stricter.'
        'A command named by a string constant (& ''ConvertFrom-Json'' $raw -Depth 5): the hook''s stripInert() blanks the quoted name before PATTERNS runs; GetCommandName() returns the constant. The script is stricter.'
        'A parameter or -Encoding value on a later physical line than the command name -- after a backtick continuation, or after an argument that spans lines such as an open parenthesis (ConvertFrom-Json -InputObject ( ... ) -Depth 5): the hook''s PATTERNS regexes test one stripped line at a time in scanFile(), so the command and the parameter never meet; the script reports at the command''s FIRST line, so a # ps51-ok must sit on or above that line. The script is stricter. One sub-case differs by LINE rather than by presence: -Encoding utf8NoBOM on a later line, which the hook''s command-free -Encoding pattern reports at the -Encoding line and the script reports at the command''s first line.'
        'A # ps51-ok inside a string or here-string, not a comment, on the finding''s line or the 6 before it: the hook''s suppressed() tests the RAW lines, strings included; the script honours only Comment tokens, each read line by line. The script is stricter.'
        'A -PSEdition parameter or a $PSEdition variable in the 6 lines before the finding: the hook''s RE_GATE \bPSEdition\b counts either as a version gate; the script counts only a bare PSEdition token (the .PSEdition member). The script is stricter.'
        'Two findings for one rule on one line (two ConvertFrom-Json -Depth commands joined by ;): the hook''s scanFile() reports once per line per PATTERNS entry; the script reports once per command. The script is stricter.'
        'A finding inside an unskipped Describe but after a nested, PSVersion-skipped Context closes: the hook''s inSkippedBlock() walks back to the nearest opener line, the Context, and reads its guard; the script reads the enclosing Describe, which has none. The script is stricter.'
        'A file-scope finding (a BeforeAll outside any block) when some unskipped Describe does not begin its line (if ($x) { Describe ... }): the hook''s allDescribesSkipped() counts only lines matching ^\s*Describe\b, so it finds every Describe skipped; the script counts every Describe CommandAst. The script is stricter.'
        'A -Skip: argument that does not read PSVersion (-Skip:$false) while PSVersion appears elsewhere in the opener''s first 3 lines (an It body on the next line): the hook''s RE_SKIP_GUARD -Skip:.*PSVersion runs over the 3 joined lines and treats the block as skipped; the script reads only the -Skip: argument''s own code tokens. The script is stricter.'
        'A # inside a bareword argument (-Uri http://h/#x, then -SkipCertificateCheck on the same line): the hook''s stripInert() blanks from every # to the end of the line; PowerShell starts a comment only at a token boundary, and the script reads the tokens. The script is stricter.'
        'A 5.1 parse error that matches none of the hook''s RE_CLASS1 patterns (an unbalanced brace, say): ps51-compat-check.mjs calls the 5.1 parser only after an RE_CLASS1 match (in scanFile()), so it never adjudicates one, and ps-parse-check.mjs reports it only if PowerShell 7 fails to parse it too. The script parses every in-scope file under 5.1 and reports it. The script is stricter.'
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
