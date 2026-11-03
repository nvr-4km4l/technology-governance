
param(
    [Parameter(Mandatory)]
    [string]$ProjectPath,

    [Parameter(Mandatory)]
    [ValidateSet("dotnet", "vue")]
    [string]$ProjectType
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    throw "Project directory not found: $ProjectPath"
}

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path

$result = [ordered]@{
    projectPath = $ProjectPath
    projectType = $ProjectType
    scanDate    = (Get-Date).ToUniversalTime().ToString("o")
    frameworks  = @()
}

if ($ProjectType -eq "dotnet") {

    $projects = @(
        Get-ChildItem -LiteralPath $ProjectPath `
            -Filter "*.csproj" -File -Recurse |
        Where-Object {
            $_.FullName -notmatch '[\\/](bin|obj)[\\/]'
        }
    )

    if ($projects.Count -eq 0) {
        throw "No .csproj files found"
    }

    foreach ($project in $projects) {

        [xml]$xml = Get-Content -LiteralPath $project.FullName -Raw

        $frameworks = @(
            foreach ($group in $xml.Project.PropertyGroup) {
                if ($group.TargetFramework) {
                    [string]$group.TargetFramework
                }
                if ($group.TargetFrameworks) {
                    ([string]$group.TargetFrameworks) -split ";"
                }
            }
        ) | Where-Object { $_ } | Select-Object -Unique

        foreach ($framework in $frameworks) {
            $result.frameworks += [ordered]@{
                name    = ".NET"
                version = $framework
                project = $project.Name
            }
        }
    }
}

if ($ProjectType -eq "vue") {

    $packageFile = Join-Path $ProjectPath "package.json"

    if (-not (Test-Path -LiteralPath $packageFile)) {
        throw "package.json not found"
    }

    $package = Get-Content -LiteralPath $packageFile -Raw |
        ConvertFrom-Json

    foreach ($name in @("vue", "vite")) {

        $version = $null

        if ($package.dependencies) {
            $version = $package.dependencies.PSObject.Properties[$name].Value
        }

        if (-not $version -and $package.devDependencies) {
            $version = $package.devDependencies.PSObject.Properties[$name].Value
        }

        if ($version) {
            $result.frameworks += [ordered]@{
                name    = $name
                version = $version
                project = $package.name
            }
        }
    }

    if ($package.engines -and $package.engines.node) {
        $result.frameworks += [ordered]@{
            name    = "Node.js"
            version = $package.engines.node
            project = $package.name
        }
    }
}

$result | ConvertTo-Json -Depth 10
