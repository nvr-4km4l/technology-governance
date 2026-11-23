
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('frontend', 'backend')]
    [string]$ProjectType,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$RepositoryName = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath $ProjectPath).Path
$projectName = if (-not [string]::IsNullOrWhiteSpace($RepositoryName)) {
    $RepositoryName
}
else {
    Split-Path $projectRoot -Leaf
}

$repositories = @()

if ($ProjectType -eq 'frontend') {

    $lockFile = Join-Path $projectRoot 'package-lock.json'

    if (-not (Test-Path -LiteralPath $lockFile)) {
        throw "package-lock.json not found: $projectRoot"
    }

    Write-Host "Scanning npm dependencies: $projectName"

    Push-Location $projectRoot

    try {
        $npmOutput = & npm audit --json 2>&1
        $npmExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    $npmText = $npmOutput -join "`n"

    if ($npmExitCode -notin @(0, 1)) {
        throw "npm audit failed with exit code $npmExitCode"
    }

    try {
        $npmAudit = $npmText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Unable to parse npm audit JSON: $($_.Exception.Message)"
    }

    if ($null -eq $npmAudit.metadata.vulnerabilities) {
        throw "npm audit returned no vulnerability summary."
    }

    $npmCounts = $npmAudit.metadata.vulnerabilities

    $npmStatus = if ($npmCounts.total -gt 0) {
        'VulnerabilitiesDetected'
    }
    else {
        'Clean'
    }

    $repositories += [ordered]@{
        project = $projectName
        ecosystem = 'npm'
        status = $npmStatus
        vulnerabilityCounts = $npmCounts
        vulnerabilities = $npmAudit.vulnerabilities
    }
}

elseif ($ProjectType -eq 'backend') {

    $projects = @(Get-ChildItem -LiteralPath $projectRoot -Filter '*.csproj' -Recurse -File)

    if ($projects.Count -eq 0) {
        throw "No .csproj files found: $projectRoot"
    }

    Write-Host "Scanning NuGet dependencies: $projectName"

    Push-Location $projectRoot

    try {
        $nugetOutput = & dotnet list package --vulnerable --include-transitive 2>&1
        $nugetExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($nugetExitCode -ne 0) {
        throw "NuGet vulnerability scan failed: $($nugetOutput -join ' ')"
    }

    $nugetText = $nugetOutput -join "`n"

    $nugetStatus = 'ReviewRequired'

    if ($nugetText -match 'has no vulnerable packages') {
        $nugetStatus = 'Clean'
    }
    elseif ($nugetText -match 'Severity|Advisory URL') {
        $nugetStatus = 'VulnerabilitiesDetected'
    }

    $repositories += [ordered]@{
        project = $projectName
        ecosystem = 'NuGet'
        status = $nugetStatus
        vulnerabilities = @()
        rawOutput = $nugetText
    }
}

$report = [ordered]@{
    reportName = 'Technology Vulnerability Report'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    repositories = $repositories
}

$outputDirectory = Split-Path -Parent $OutputPath

if ($outputDirectory) {
    New-Item -ItemType Directory -Path $outputDirectory -Force |
        Out-Null
}

$report |
    ConvertTo-Json -Depth 30 |
    Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Host "Developer vulnerability report generated successfully!"
Write-Host "Report: $OutputPath"
