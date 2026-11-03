
param(
    [string]$BackendPath = 'C:\project\poc-backend',
    [string]$FrontendPath = 'C:\project\poc-frontend'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

$detector = Join-Path $PSScriptRoot 'detect-framework.ps1'

# Scan .NET backend
$backendJson = & $detector `
    -ProjectPath $BackendPath `
    -ProjectType 'dotnet'

$backend = $backendJson | ConvertFrom-Json

# Scan Vue frontend
$frontendJson = & $detector `
    -ProjectPath $FrontendPath `
    -ProjectType 'vue'

$frontend = $frontendJson | ConvertFrom-Json

# Generate centralized report
$report = [ordered]@{
    reportName   = 'Technology Health Report'
    generatedAt  = (Get-Date).ToUniversalTime().ToString('o')
    repositories = @($backend, $frontend)
}

# Create reports directory
$reportsDir = Join-Path $root 'reports'

New-Item -ItemType Directory -Force -Path $reportsDir |
    Out-Null

# Save JSON report
$output = Join-Path $reportsDir 'technology-health-report.json'

$report |
    ConvertTo-Json -Depth 15 |
    Set-Content -LiteralPath $output -Encoding utf8

Write-Host 'Technology health report generated successfully!'
Write-Host "Report location: $output"
