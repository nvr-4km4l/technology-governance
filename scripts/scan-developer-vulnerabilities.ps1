
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

    $projects = @(
        Get-ChildItem -LiteralPath $projectRoot `
            -Filter '*.csproj' -Recurse -File
    )

    if ($projects.Count -eq 0) {
        throw "No .csproj files found: $projectRoot"
    }

    Write-Host "Scanning NuGet dependencies: $projectName"

    $nugetFindings = @()

    foreach ($project in $projects) {

        Write-Host "Scanning project: $($project.Name)"

        $nugetOutput = & dotnet list $project.FullName package `
            --vulnerable `
            --include-transitive `
            --format json 2>&1

        $nugetExitCode = $LASTEXITCODE

        if ($nugetExitCode -ne 0) {
            throw "NuGet scan failed for $($project.Name): $($nugetOutput -join ' ')"
        }

        $nugetText = $nugetOutput -join "`n"

        try {
            $nugetReport = $nugetText | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Unable to parse NuGet JSON for $($project.Name): $($_.Exception.Message)"
        }

        foreach ($nugetProject in @($nugetReport.projects)) {

            foreach ($framework in @($nugetProject.frameworks)) {

                $packages = @(
                    @($framework.topLevelPackages) +
                    @($framework.transitivePackages)
                ) | Where-Object { $null -ne $_ }

                foreach ($package in $packages) {

                    foreach ($advisory in @($package.vulnerabilities)) {

                        if ($null -eq $advisory) {
                            continue
                        }

                        $nugetFindings += [PSCustomObject]@{
                            package = $package.id
                            version = $package.resolvedVersion
                            severity = $advisory.severity
                            advisoryUrl = $advisory.advisoryurl
                            projectFile = $project.Name
                            framework = $framework.framework
                        }
                    }
                }
            }
        }
    }

    $nugetStatus = if ($nugetFindings.Count -gt 0) {
        'VulnerabilitiesDetected'
    }
    else {
        'Clean'
    }

    $repositories += [ordered]@{
        project = $projectName
        ecosystem = 'NuGet'
        status = $nugetStatus
        vulnerabilityCounts = [ordered]@{
            total = $nugetFindings.Count
        }
        vulnerabilities = @($nugetFindings)
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
