
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('frontend', 'backend', 'vue', 'dotnet', 'auto')]
    [string]$ProjectType,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path

$detector = Join-Path $PSScriptRoot 'detect-framework.ps1'
$lifecycleChecker = Join-Path $PSScriptRoot 'check-lifecycle.ps1'

# Map developer input to supported scanner type
switch ($ProjectType) {
    'frontend' { $scanType = 'vue' }
    'backend'  { $scanType = 'dotnet' }
    'vue'      { $scanType = 'vue' }
    'dotnet'   { $scanType = 'dotnet' }
    'auto' {
        if (Test-Path (Join-Path $ProjectPath 'package.json')) {
            $scanType = 'vue'
        }
        elseif (@(Get-ChildItem -LiteralPath $ProjectPath -Filter '*.csproj' -File -Recurse).Count -gt 0) {
            $scanType = 'dotnet'
        }
        else {
            throw "Unable to detect supported project type."
        }
    }
}

Write-Host "Developer project: $ProjectPath"
Write-Host "Scan type: $scanType"

# Run existing framework detector
$detectedJson = & $detector `
    -ProjectPath $ProjectPath `
    -ProjectType $scanType

$detected = $detectedJson | ConvertFrom-Json

# Enrich .NET frameworks with lifecycle information
if ($scanType -eq 'dotnet') {
    foreach ($framework in $detected.frameworks) {
        if ($framework.name -eq '.NET') {
            $lifecycleJson = & $lifecycleChecker `
                -Framework $framework.name `
                -Version $framework.version

            $lifecycle = $lifecycleJson | ConvertFrom-Json

            foreach ($property in @(
                'lifecycleStatus',
                'supportType',
                'endOfSupport',
                'dataSource',
                'metadataPhase'
            )) {
                $framework | Add-Member `
                    -NotePropertyName $property `
                    -NotePropertyValue $lifecycle.$property `
                    -Force
            }
        }
    }
}

# Preserve existing report schema
$report = [ordered]@{
    reportName = 'Technology Health Report'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    repositories = @($detected)
}

$outputDirectory = Split-Path -Parent $OutputPath

if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory |
        Out-Null
}

$report |
    ConvertTo-Json -Depth 15 |
    Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Host "Technology health report generated successfully!"
Write-Host "Report location: $OutputPath"
