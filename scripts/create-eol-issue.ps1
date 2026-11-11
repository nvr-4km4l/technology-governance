
param(
    [string]$ReportPath = "$PSScriptRoot\..\reports\technology-health-report.json",
    [switch]$CreateIssue,
    [string]$IssueRepository = 'nvr-4km4l/technology-governance'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ReportPath)) {
    throw "Report not found: $ReportPath"
}

$report = Get-Content -LiteralPath $ReportPath -Raw |
    ConvertFrom-Json

$eolFrameworks = @(
    foreach ($repo in $report.repositories) {
        foreach ($framework in $repo.frameworks) {
            if ($framework.lifecycleStatus -eq 'End of Support') {
                [PSCustomObject]@{
                    Repository   = $repo.projectPath
                    ProjectType  = $repo.projectType
                    Framework    = $framework.name
                    Version      = $framework.version
                    EndOfSupport = $framework.endOfSupport
                }
            }
        }
    }
)

if ($eolFrameworks.Count -eq 0) {
    Write-Host "No EOL frameworks detected."
    return
}

foreach ($item in $eolFrameworks) {

    $title = "[Technology Governance] EOL: $($item.Framework) $($item.Version) ($($item.ProjectType))"

    Write-Host "EOL WARNING: $title"

    if (-not $CreateIssue) {
        Write-Host "DRY RUN: Issue would be created."
        continue
    }

    if (-not $env:GH_TOKEN) {
        throw 'GH_TOKEN is not available.'
    }

    $body = @"
## End-of-Support Warning

**Framework:** $($item.Framework)
**Version:** $($item.Version)
**Project Type:** $($item.ProjectType)
**End of Support:** $($item.EndOfSupport)

The framework was detected as End of Support by the Technology Governance scanner.

**Recommended action:** Review the project and plan an upgrade to a supported framework version.

Generated automatically by Technology Governance.
"@

    # Check existing open issues to prevent duplicates
    $existing = gh issue list `
        --repo $IssueRepository `
        --state open `
        --limit 1000 `
        --json title |
        ConvertFrom-Json

    if (@($existing | Where-Object { $_.title -eq $title }).Count -gt 0) {
        Write-Host "Existing issue found. Skipping: $title"
        continue
    }

    gh issue create `
        --repo $IssueRepository `
        --title $title `
        --body $body

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create GitHub Issue: $title"
    }
}

Write-Host "EOL issue processing completed."
