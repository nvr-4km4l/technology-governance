
param(
    [string]$BackendPath = 'C:\project\poc-backend',
    [string]$FrontendPath = 'C:\project\poc-frontend',
    [string]$OutputPath = "$PSScriptRoot\..\reports\vulnerability-report.json"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $BackendPath 'poc-backend.csproj'))) {
    throw "Backend project not found: $BackendPath"
}

if (-not (Test-Path (Join-Path $FrontendPath 'package-lock.json'))) {
    throw "Frontend package-lock.json not found: $FrontendPath"
}

Write-Host 'Scanning backend NuGet dependencies...'

Push-Location $BackendPath
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

# Keep full scanner output; do not mistake unparsed results for zero findings.
$nugetStatus = 'ReviewRequired'
$nugetVulnerabilities = @()

if ($nugetText -match 'has no vulnerable packages') {
    $nugetStatus = 'Clean'
}
elseif ($nugetText -match 'Severity|Advisory URL') {
    $nugetStatus = 'VulnerabilitiesDetected'
}

Write-Host 'Scanning frontend npm dependencies...'

Push-Location $FrontendPath
try {
    $npmOutput = & npm audit --json 2>&1
    $npmExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

$npmText = $npmOutput -join "`n"

try {
    $npmAudit = $npmText | ConvertFrom-Json
}
catch {
    throw "Unable to parse npm audit JSON: $($_.Exception.Message)"
}

if ($npmExitCode -notin @(0, 1)) {
    throw "npm audit failed with exit code $npmExitCode"
}

if (-not $npmAudit.metadata.vulnerabilities) {
    throw 'npm audit returned no vulnerability summary.'
}

$npmCounts = $npmAudit.metadata.vulnerabilities

$npmStatus = if ($npmCounts.total -gt 0) {
    'VulnerabilitiesDetected'
}
else {
    'Clean'
}

$report = [ordered]@{
    reportName = 'Technology Vulnerability Report'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    repositories = @(
        [ordered]@{
            project = 'poc-backend'
            ecosystem = 'NuGet'
            status = $nugetStatus
            vulnerabilities = $nugetVulnerabilities
            rawOutput = $nugetText
        },
        [ordered]@{
            project = 'poc-frontend'
            ecosystem = 'npm'
            status = $npmStatus
            vulnerabilityCounts = $npmCounts
            vulnerabilities = $npmAudit.vulnerabilities
        }
    )
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force |
    Out-Null

$report |
    ConvertTo-Json -Depth 30 |
    Set-Content -Path $OutputPath -Encoding utf8

Write-Host 'Vulnerability report generated successfully!'
Write-Host "Report location: $OutputPath"
Write-Host "Backend status: $nugetStatus"
Write-Host "Frontend status: $npmStatus"
