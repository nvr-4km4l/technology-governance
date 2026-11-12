
param(
    [Parameter(Mandatory = $true)]
    [string]$PreviousReport,

    [Parameter(Mandatory = $true)]
    [string]$CurrentReport,

    [string]$OutputPath = "$PSScriptRoot\..\reports\framework-change-report.json"
)

$ErrorActionPreference = 'Stop'

foreach ($path in @($PreviousReport, $CurrentReport)) {
    if (-not (Test-Path $path)) {
        throw "Report not found: $path"
    }
}

$previous = Get-Content $PreviousReport -Raw | ConvertFrom-Json
$current = Get-Content $CurrentReport -Raw | ConvertFrom-Json

function Get-FrameworkInventory {
    param($Report)

    $inventory = @{}

    foreach ($repo in $Report.repositories) {
        foreach ($framework in $repo.frameworks) {

            $key = "$($repo.projectType)|$($framework.project)|$($framework.name)"

            $inventory[$key] = [PSCustomObject]@{
                projectType = $repo.projectType
                project = $framework.project
                framework = $framework.name
                version = $framework.version
            }
        }
    }

    return $inventory
}

$previousInventory = Get-FrameworkInventory $previous
$currentInventory = Get-FrameworkInventory $current

$allKeys = @(
    $previousInventory.Keys
    $currentInventory.Keys
) | Sort-Object -Unique

$changes = @()

foreach ($key in $allKeys) {

    $old = $previousInventory[$key]
    $new = $currentInventory[$key]

    if (-not $old) {
        $status = 'Added'
    }
    elseif (-not $new) {
        $status = 'Removed'
    }
    elseif ($old.version -ne $new.version) {
        $status = 'VersionChanged'
    }
    else {
        $status = 'Unchanged'
    }

    $changes += [PSCustomObject]@{
        projectType = if ($new) { $new.projectType } else { $old.projectType }
        project = if ($new) { $new.project } else { $old.project }
        framework = if ($new) { $new.framework } else { $old.framework }
        previousVersion = if ($old) { $old.version } else { $null }
        currentVersion = if ($new) { $new.version } else { $null }
        status = $status
    }
}

$summary = [ordered]@{
    added = @($changes | Where-Object status -eq 'Added').Count
    removed = @($changes | Where-Object status -eq 'Removed').Count
    versionChanged = @($changes | Where-Object status -eq 'VersionChanged').Count
    unchanged = @($changes | Where-Object status -eq 'Unchanged').Count
}

$result = [ordered]@{
    reportName = 'Framework Change Report'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    summary = $summary
    changes = $changes
}

New-Item -ItemType Directory `
    -Path (Split-Path -Parent $OutputPath) `
    -Force | Out-Null

$result |
    ConvertTo-Json -Depth 20 |
    Set-Content $OutputPath -Encoding utf8

Write-Host 'Framework comparison completed successfully!'
Write-Host "Added: $($summary.added)"
Write-Host "Removed: $($summary.removed)"
Write-Host "Version changed: $($summary.versionChanged)"
Write-Host "Unchanged: $($summary.unchanged)"
Write-Host "Report: $OutputPath"
