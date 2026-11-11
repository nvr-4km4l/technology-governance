
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

# Check lifecycle for detected .NET frameworks
$lifecycleChecker = Join-Path $PSScriptRoot 'check-lifecycle.ps1'

foreach ($framework in $backend.frameworks) {

    if ($framework.name -eq '.NET') {

        $lifecycleJson = & $lifecycleChecker `
            -Framework $framework.name `
            -Version $framework.version

        $lifecycle = $lifecycleJson | ConvertFrom-Json

        $framework | Add-Member `
            -NotePropertyName 'lifecycleStatus' `
            -NotePropertyValue $lifecycle.lifecycleStatus -Force

        $framework | Add-Member `
            -NotePropertyName 'supportType' `
            -NotePropertyValue $lifecycle.supportType -Force

        $framework | Add-Member `
            -NotePropertyName 'endOfSupport' `
            -NotePropertyValue $lifecycle.endOfSupport -Force
    }
}

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


Write-Host "Backend source: $BackendPath"
Write-Host "Frontend source: $FrontendPath"

if (-not (Test-Path -LiteralPath $BackendPath -PathType Container)) {
    throw "Backend directory not found: $BackendPath"
}

if (-not (Test-Path -LiteralPath $FrontendPath -PathType Container)) {
    throw "Frontend directory not found: $FrontendPath"
}

$report |
    ConvertTo-Json -Depth 15 |
    Set-Content -LiteralPath $output -Encoding utf8

Write-Host "Backend source: $BackendPath"
Write-Host "Frontend source: $FrontendPath"
Write-Host "Technology health report generated successfully!"
Write-Host "Report location: $output"

