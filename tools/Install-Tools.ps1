param([switch]$SkipBlender)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$toolsRoot = Join-Path $projectRoot '.tools'
$downloadRoot = Join-Path $toolsRoot 'downloads'
New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
function Get-Archive($Url, $Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Output "Baixando $(Split-Path $Path -Leaf)"
        Invoke-WebRequest -Uri $Url -OutFile $Path
    }
}
$godotVersion = '4.7.2'
$godotRoot = Join-Path $toolsRoot 'godot'
if (-not (Test-Path -LiteralPath (Join-Path $godotRoot "Godot_v$godotVersion-stable_win64.exe"))) {
    $release = Invoke-RestMethod "https://api.github.com/repos/godotengine/godot-builds/releases/tags/$godotVersion-stable"
    $names = @("Godot_v$godotVersion-stable_win64.exe.zip", "Godot_v$godotVersion-stable_export_templates.tpz", 'SHA512-SUMS.txt')
    foreach ($name in $names) {
        $asset = $release.assets | Where-Object name -eq $name | Select-Object -First 1
        if (-not $asset) { throw "Artefato oficial ausente: $name" }
        Get-Archive $asset.browser_download_url (Join-Path $downloadRoot $name)
    }
    $checksums = Get-Content (Join-Path $downloadRoot 'SHA512-SUMS.txt')
    foreach ($name in $names[0..1]) {
        $entry = $checksums | Where-Object { $_ -match ([regex]::Escape($name) + '$') } | Select-Object -First 1
        $expected = ($entry -split '\s+')[0]
        if (-not $expected -or (Get-FileHash (Join-Path $downloadRoot $name) -Algorithm SHA512).Hash -ne $expected) {
            throw "Checksum inválido: $name"
        }
    }
    Expand-Archive (Join-Path $downloadRoot $names[0]) $godotRoot -Force
    New-Item -ItemType File -Force (Join-Path $godotRoot '_sc_') | Out-Null
    $templateZip = Join-Path $downloadRoot 'templates.zip'
    Copy-Item -LiteralPath (Join-Path $downloadRoot $names[1]) -Destination $templateZip
    Expand-Archive $templateZip (Join-Path $downloadRoot 'template-extract') -Force
    $templateRoot = Join-Path $godotRoot "editor_data/export_templates/$godotVersion.stable"
    New-Item -ItemType Directory -Force $templateRoot | Out-Null
    Copy-Item -Path (Join-Path $downloadRoot 'template-extract/templates/*') -Destination $templateRoot -Recurse -Force
}
& (Join-Path $godotRoot "Godot_v$godotVersion-stable_win64_console.exe") --version
if (-not $SkipBlender) {
    $blenderName = 'blender-4.5.3-windows-x64'
    $blenderRoot = Join-Path $toolsRoot $blenderName
    if (-not (Test-Path -LiteralPath (Join-Path $blenderRoot 'blender.exe'))) {
        $archive = Join-Path $downloadRoot "$blenderName.zip"
        Get-Archive "https://download.blender.org/release/Blender4.5/$blenderName.zip" $archive
        $checksumPath = Join-Path $downloadRoot 'blender-4.5.3.sha256'
        Get-Archive 'https://download.blender.org/release/Blender4.5/blender-4.5.3.sha256' $checksumPath
        $entry = Get-Content $checksumPath | Where-Object { $_ -match ([regex]::Escape("$blenderName.zip") + '$') } | Select-Object -First 1
        if (-not $entry -or (Get-FileHash $archive -Algorithm SHA256).Hash -ne ($entry -split '\s+')[0]) {
            throw 'Checksum Blender inválido'
        }
        Expand-Archive $archive $toolsRoot -Force
    }
    & (Join-Path $blenderRoot 'blender.exe') --background --factory-startup --version
}
Write-Output 'Ferramentas portáteis prontas. Nenhuma entrada de inicialização foi criada.'
