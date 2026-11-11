
param(
    [Parameter(Mandatory = $true)]
    [string]$Framework,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [datetime]$AsOfDate = (Get-Date)
)

$ErrorActionPreference = 'Stop'

# Microsoft .NET support dates
# Source: https://dotnet.microsoft.com/en-us/platform/support/policy
$dotnetLifecycle = @{
    '6'  = @{ EndOfSupport = '2024-11-12'; Type = 'LTS' }
    '8'  = @{ EndOfSupport = '2026-11-10'; Type = 'LTS' }
    '9'  = @{ EndOfSupport = '2026-11-10'; Type = 'STS' }
    '10' = @{ EndOfSupport = '2028-11-14'; Type = 'LTS' }
    '11' = @{ EndOfSupport = '2028-11-14'; Type = 'STS' }
}

$result = [ordered]@{
    framework    = $Framework
    version      = $Version
    lifecycleStatus = 'Unknown'
    supportType  = $null
    endOfSupport = $null
    checkedAt    = $AsOfDate.ToString('yyyy-MM-dd')
}

if ($Framework -eq '.NET') {

    if ($Version -match '^net(\d+)\.\d+$') {
        $majorVersion = $Matches[1]

        if ($dotnetLifecycle.ContainsKey($majorVersion)) {

            $info = $dotnetLifecycle[$majorVersion]
            $eolDate = [datetime]::ParseExact(
                $info.EndOfSupport,
                'yyyy-MM-dd',
                [System.Globalization.CultureInfo]::InvariantCulture
            )

            $result.supportType = $info.Type
            $result.endOfSupport = $info.EndOfSupport

            if ($AsOfDate.Date -gt $eolDate.Date) {
                $result.lifecycleStatus = 'End of Support'
            }
            else {
                $result.lifecycleStatus = 'Supported'
            }
        }
    }
}

$result | ConvertTo-Json -Depth 5
