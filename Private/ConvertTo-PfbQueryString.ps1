function ConvertTo-PfbQueryString {
    <#
    .SYNOPSIS
        Converts a hashtable of query parameters into a URL query string.
    .DESCRIPTION
        Builds the query string for FlashBlade REST API calls. Skips null/empty values.
        Handles array values by joining with commas.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Parameters
    )

    if (-not $Parameters -or $Parameters.Count -eq 0) {
        return ''
    }

    $parts = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrEmpty($value))) {
            continue
        }

        if ($value -is [array]) {
            $value = $value -join ','
        }

        $encodedKey = [System.Uri]::EscapeDataString($key)
        $encodedValue = [System.Uri]::EscapeDataString($value.ToString())
        $parts.Add("${encodedKey}=${encodedValue}")
    }

    if ($parts.Count -eq 0) {
        return ''
    }

    return '?' + ($parts -join '&')
}
