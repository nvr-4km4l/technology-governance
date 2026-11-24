
param(
    [Parameter(Mandatory)]
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'

# Validate project root
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    throw "Project directory not found: $ProjectPath"
}

$projectRoot = (Resolve-Path -LiteralPath $ProjectPath).Path

$rootPrefix = $projectRoot.TrimEnd('\', '/') +
    [System.IO.Path]::DirectorySeparatorChar

$excludedPattern = '[\\/](bin|obj|\.git|\.vs|node_modules)[\\/]'

# Store unique project paths
$projectPaths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

# Discover solution files
$solutions = @(
    Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
        Where-Object {
            $_.Extension -in @('.sln', '.slnx') -and
            $_.FullName -notmatch $excludedPattern
        }
)

if ($solutions.Count -gt 0) {

    Write-Host "Discovery mode: Solution-aware"
    Write-Host "Solutions found: $($solutions.Count)"

    foreach ($solution in $solutions) {

        Write-Host "Reading solution: $($solution.Name)"

        $solutionOutput = @(
            & dotnet sln $solution.FullName list 2>&1
        )

        $solutionExitCode = $LASTEXITCODE

        if ($solutionExitCode -ne 0) {
            throw "Unable to read solution $($solution.Name): $($solutionOutput -join ' ')"
        }

        $registeredProjects = @(
            $solutionOutput |
                ForEach-Object { "$_".Trim() } |
                Where-Object { $_ -match '\.csproj$' }
        )

        foreach ($relativePath in $registeredProjects) {

            $fullPath = [System.IO.Path]::GetFullPath(
                $relativePath,
                $solution.DirectoryName
            )

            # Reject projects outside the scan root
            if (-not $fullPath.StartsWith(
                $rootPrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
                throw "Project outside scan root: $fullPath"
            }

            if ($fullPath -match $excludedPattern) {
                throw "Registered project is in an excluded directory: $fullPath"
            }

            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                throw "Registered project not found: $fullPath"
            }

            [void]$projectPaths.Add($fullPath)
        }
    }
}
else {

    Write-Host "Discovery mode: Standalone project"

    $standaloneProjects = @(
        Get-ChildItem -LiteralPath $projectRoot `
            -Filter '*.csproj' -Recurse -File |
            Where-Object {
                $_.FullName -notmatch $excludedPattern
            }
    )

    foreach ($project in $standaloneProjects) {
        [void]$projectPaths.Add($project.FullName)
    }
}

# Prevent an empty project list
if ($projectPaths.Count -eq 0) {
    throw "No valid .csproj files found: $projectRoot"
}

Write-Host "Unique projects discovered: $($projectPaths.Count)"

# Return FileInfo objects for compatibility with existing scanners
foreach ($path in ($projectPaths | Sort-Object)) {
    Get-Item -LiteralPath $path
}
