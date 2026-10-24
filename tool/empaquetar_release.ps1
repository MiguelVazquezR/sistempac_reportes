<#
.SYNOPSIS
Empaqueta el build de Windows en un ZIP portatil listo para copiar a otro equipo.

.DESCRIPTION
El .exe de Flutter no funciona solo: necesita las DLL del motor y de los plugins
junto a el, mas la carpeta data\ con app.so, icudtl.dat y flutter_assets\.
Por eso se comprime la carpeta Release completa.

El ZIP resultante se descomprime integro en el equipo destino y se ejecuta
reportes_sistempac.exe. No hace falta Flutter ni Visual Studio en ese equipo.

Los textos se escriben sin acentos para que el script se ejecute igual en
consolas con codificacion ANSI (PowerShell 5.1).

.EXAMPLE
powershell -ExecutionPolicy Bypass -File tool\empaquetar_release.ps1
#>
[CmdletBinding()]
param(
    [string]$Configuracion = 'Release',
    [string]$Nombre = 'OptimizadorReportes',
    [string]$Salida
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot no esta disponible al enlazar los parametros; por eso la raiz se
# calcula aqui.
$carpetaScript = $PSScriptRoot
if (-not $carpetaScript) { $carpetaScript = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$raiz = [System.IO.Path]::GetFullPath((Join-Path $carpetaScript '..'))
$release = Join-Path $raiz "build\windows\x64\runner\$Configuracion"
$exe = Join-Path $release 'reportes_sistempac.exe'

if (-not (Test-Path -LiteralPath $exe)) {
    throw "No existe $exe. Ejecuta primero: flutter build windows --release"
}

# Archivos sin los cuales la aplicacion no arranca en el equipo destino.
$obligatorios = @(
    'reportes_sistempac.exe',
    'flutter_windows.dll',
    'data\app.so',
    'data\icudtl.dat',
    'data\flutter_assets'
)
$faltantes = @()
foreach ($relativo in $obligatorios) {
    if (-not (Test-Path -LiteralPath (Join-Path $release $relativo))) { $faltantes += $relativo }
}
if ($faltantes.Count -gt 0) {
    throw ("El bundle esta incompleto, falta: " + ($faltantes -join ', '))
}

# Version desde pubspec.yaml (por ejemplo 1.0.0+1 -> 1.0.0).
$version = '1.0.0'
$linea = Select-String -LiteralPath (Join-Path $raiz 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if ($linea) { $version = ($linea.Matches[0].Groups[1].Value -split '\+')[0] }

$dist = if ($Salida) { [System.IO.Path]::GetFullPath($Salida) } else { Join-Path $raiz 'dist' }
if (-not (Test-Path -LiteralPath $dist)) {
    New-Item -ItemType Directory -Path $dist | Out-Null
}

$zip = Join-Path $dist "$Nombre-$version-win64.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }

Write-Host "Origen : $release"
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $zip -CompressionLevel Optimal

$archivos = Get-ChildItem -LiteralPath $release -Recurse -File
$pesoZip = (Get-Item -LiteralPath $zip).Length
Write-Host ("Paquete: {0} ({1:N1} MB, {2} archivos, version {3})" -f $zip, ($pesoZip / 1MB), $archivos.Count, $version)
Write-Host ""
Write-Host "En el equipo destino:"
Write-Host "  1. Descomprime el ZIP completo en C:\Program Files\OptimizadorReportes"
Write-Host "  2. Ejecuta reportes_sistempac.exe (mismas DLL y carpeta data\ al lado)"
Write-Host "  3. Si falta VCRUNTIME140.dll, instala el VC++ Redistributable 2015-2022 x64"
