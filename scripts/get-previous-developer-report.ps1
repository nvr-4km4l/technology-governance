
param(
    [Parameter(Mandatory)]
    [string]$Repository,

    [Parameter(Mandatory)]
    [string]$CurrentRunId,

    [Parameter(Mandatory)]
    [string]$Branch,

    [Parameter(Mandatory)]
    [string]$CurrentReport,

    [Parameter(Mandatory)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $CurrentReport -PathType Leaf)) {
    throw "Current report not found: $CurrentReport"
}

if (-not $env:GH_TOKEN) {
    throw "GH_TOKEN is not configured."
}

$workspace = Join-Path $env:TEMP "developer-baseline-$CurrentRunId"

New-Item -ItemType Directory -Path $workspace -Force |
    Out-Null

try {
    Write-Host "Searching previous developer governance runs..."
    Write-Host "Repository: $Repository"
    Write-Host "Branch: $Branch"

    $runsJson = gh run list `
        --repo $Repository `
        --workflow governance.yml `
        --branch $Branch `
        --status success `
        --limit 100 `
        --json databaseId,createdAt

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve workflow history."
    }

    $runs = @($runsJson | ConvertFrom-Json) |
        Sort-Object createdAt -Descending

    $matched = $false

    foreach ($run in $runs) {
        $runId = [string]$run.databaseId

        if ($runId -eq $CurrentRunId) {
            continue
        }

        $runFolder = Join-Path $workspace $runId

        New-Item -ItemType Directory -Path $runFolder -Force |
            Out-Null

        $null = gh run download $runId `
            --repo $Repository `
            --name technology-health-report `
            --dir $runFolder 2>$null

        if ($LASTEXITCODE -ne 0) {
            continue
        }

        $healthPath = Join-Path $runFolder 'technology-health-report.json'

        if (-not (Test-Path -LiteralPath $healthPath -PathType Leaf)) {
            continue
        }

        try {
            $report = Get-Content -LiteralPath $healthPath -Raw |
                ConvertFrom-Json -ErrorAction Stop

            if (-not $report.repositories) {
                throw "Missing repositories data."
            }
        }
        catch {
            Write-Warning "Invalid report in run $runId. Skipping."
            continue
        }

        $destination = Split-Path -Parent $OutputPath

        if ($destination) {
            New-Item -ItemType Directory -Path $destination -Force |
                Out-Null
        }

        Copy-Item -LiteralPath $healthPath `
            -Destination $OutputPath -Force

        Write-Host "Previous developer baseline retrieved!"
        Write-Host "Previous run: $runId"

        $matched = $true
        break
    }

    if (-not $matched) {
        Write-Host "No previous baseline found."
        Write-Host "Initializing baseline from current report."

        $destination = Split-Path -Parent $OutputPath

        if ($destination) {
            New-Item -ItemType Directory -Path $destination -Force |
                Out-Null
        }

        Copy-Item -LiteralPath $CurrentReport `
            -Destination $OutputPath -Force
    }

    Write-Host "Baseline saved: $OutputPath"
}
finally {
    Remove-Item -LiteralPath $workspace `
        -Recurse -Force -ErrorAction SilentlyContinue
}
