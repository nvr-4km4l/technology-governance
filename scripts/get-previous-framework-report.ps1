
param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [string]$CurrentRunId,

    [Parameter(Mandatory = $true)]
    [string]$BackendRef,

    [Parameter(Mandatory = $true)]
    [string]$FrontendRef,

    [Parameter(Mandatory = $true)]
    [string]$CurrentReport,

    [string]$OutputPath = "governance/reports/previous-framework-report.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $CurrentReport)) {
    throw "Current framework report not found: $CurrentReport"
}

if (-not $env:GH_TOKEN) {
    throw "GH_TOKEN is not configured."
}

$workspace = Join-Path $env:TEMP "governance-baseline-$CurrentRunId"
New-Item -ItemType Directory -Path $workspace -Force | Out-Null

try {
    Write-Host "Searching previous successful workflow runs..."
    Write-Host "Backend: $BackendRef"
    Write-Host "Frontend: $FrontendRef"

    $runsJson = gh run list `
        --repo $Repository `
        --workflow framework-scan.yml `
        --branch main `
        --status success `
        --limit 100 `
        --json databaseId,createdAt

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve workflow history."
    }

    $runs = @($runsJson | ConvertFrom-Json)
    $runs = @($runs | Sort-Object createdAt -Descending)

    $matched = $false

    foreach ($run in $runs) {
        $runId = [string]$run.databaseId

        if ($runId -eq $CurrentRunId) {
            continue
        }

        $runFolder = Join-Path $workspace $runId
        New-Item -ItemType Directory -Path $runFolder -Force | Out-Null

        # Only consider runs with scan-configuration metadata.
        $null = gh run download $runId `
            --repo $Repository `
            --name scan-configuration `
            --dir $runFolder 2>$null

        if ($LASTEXITCODE -ne 0) {
            continue
        }

        $configPath = Join-Path $runFolder "scan-configuration.json"

        if (-not (Test-Path $configPath)) {
            continue
        }

        try {
            $config = Get-Content $configPath -Raw |
                ConvertFrom-Json
        }
        catch {
            Write-Warning "Invalid metadata in run $runId. Skipping."
            continue
        }

        if (
            $config.backendRef -ne $BackendRef -or
            $config.frontendRef -ne $FrontendRef
        ) {
            continue
        }

        Write-Host "Matching run found: $runId"

        $healthFolder = Join-Path $runFolder "health"
        New-Item -ItemType Directory -Path $healthFolder -Force |
            Out-Null

        $null = gh run download $runId `
            --repo $Repository `
            --name technology-health-report `
            --dir $healthFolder 2>$null

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Health artifact unavailable for run $runId."
            continue
        }

        $healthPath = Join-Path $healthFolder "technology-health-report.json"

        if (-not (Test-Path $healthPath)) {
            continue
        }

        try {
            $null = Get-Content $healthPath -Raw |
                ConvertFrom-Json
        }
        catch {
            Write-Warning "Invalid health report in run $runId."
            continue
        }

        $destination = Split-Path $OutputPath -Parent

        if ($destination) {
            New-Item -ItemType Directory -Path $destination -Force |
                Out-Null
        }

        Copy-Item $healthPath $OutputPath -Force

        Write-Host "Previous baseline retrieved successfully!"
        Write-Host "Previous run: $runId"
        Write-Host "Baseline: $OutputPath"

        $matched = $true
        break
    }

    if (-not $matched) {
        Write-Host "No matching previous baseline found."
        Write-Host "Initializing baseline from current report."

        $destination = Split-Path $OutputPath -Parent

        if ($destination) {
            New-Item -ItemType Directory -Path $destination -Force |
                Out-Null
        }

        Copy-Item $CurrentReport $OutputPath -Force
    }
}
finally {
    Remove-Item $workspace -Recurse -Force -ErrorAction SilentlyContinue
}
