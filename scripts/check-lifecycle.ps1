
param(
    [Parameter(Mandatory = $true)]
    [string]$Framework,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [datetime]$AsOfDate = (Get-Date)
)

$ErrorActionPreference = 'Stop'

$metadataUrl = 'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json'

$result = [ordered]@{
    framework       = $Framework
    version         = $Version
    lifecycleStatus = 'Unknown'
    supportType     = $null
    endOfSupport    = $null
    checkedAt       = $AsOfDate.ToString('yyyy-MM-dd')
    dataSource      = $null
    metadataPhase   = $null
}

# Currently supports modern .NET target frameworks
if ($Framework -ne '.NET' -or $Version -notmatch '^net(\d+)\.(\d+)$') {
    $result | ConvertTo-Json -Depth 5
    return
}

$channelVersion = "$($Matches[1]).$($Matches[2])"

try {
    $metadata = Invoke-RestMethod `
        -Uri $metadataUrl `
        -Method Get `
        -TimeoutSec 30

    if (-not $metadata.'releases-index') {
        throw 'Microsoft lifecycle metadata is empty or invalid.'
    }

    $channel = $metadata.'releases-index' |
        Where-Object { $_.'channel-version' -eq $channelVersion } |
        Select-Object -First 1

    if (-not $channel) {
        Write-Warning "No lifecycle metadata for .NET $channelVersion"
    }
    else {
        $eolText = $channel.'eol-date'
        $phase = $channel.'support-phase'

        if (-not $eolText -or -not $phase) {
            throw "Incomplete lifecycle metadata for .NET $channelVersion"
        }

        $eolDate = [datetime]::ParseExact(
            $eolText,
            'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture
        )

        $result.supportType = $channel.'release-type'.ToUpperInvariant()
        $result.endOfSupport = $eolText
        $result.metadataPhase = $phase
        $result.dataSource = $metadataUrl

        if ($AsOfDate.Date -gt $eolDate.Date -or $phase -eq 'eol') {
            $result.lifecycleStatus = 'End of Support'
        }
        elseif ($phase -in @('active', 'maintenance', 'go-live')) {
            $result.lifecycleStatus = 'Supported'
        }
        else {
            $result.lifecycleStatus = 'Unknown'
        }
    }
}
catch {
    throw "Failed to retrieve or validate Microsoft lifecycle metadata: $($_.Exception.Message)"
}

$result | ConvertTo-Json -Depth 5
