function Test-PfbSyslogServer {
    <#
    .SYNOPSIS
        Tests all configured syslog servers on a FlashBlade array.
    .DESCRIPTION
        The Test-PfbSyslogServer cmdlet tests the connectivity and configuration of all
        configured syslog servers on the connected FlashBlade. The API does not provide a
        way to scope this test to a specific server, so use Where-Object to narrow the
        returned results on the client side.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbSyslogServer

        Tests all configured syslog servers.
    .EXAMPLE
        Test-PfbSyslogServer | Where-Object component_name -eq "syslog-prod"

        Tests all configured syslog servers and displays the result for "syslog-prod".
        The API provides no way to scope the test request to one server.
    .EXAMPLE
        Test-PfbSyslogServer | Select-Object component_name, result_details

        Tests all configured syslog servers and displays their detailed results.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'syslog-servers/test' -QueryParams $queryParams
}
