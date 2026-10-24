<#
.SYNOPSIS
Genera el icono del ejecutable de Windows (app_icon.ico) a partir de lib/images/icon.png.

.DESCRIPTION
Flutter incrusta en el .exe el icono que referencia windows/runner/Runner.rc
(IDI_APP_ICON -> resources\app_icon.ico), y ese archivo trae el icono por defecto
de Flutter. Este script lo sustituye por uno generado desde lib/images/icon.png.

El .ico se genera con varios tamanos en un mismo archivo:
  - 256 px como PNG (formato recomendado por Windows para el tamano grande).
  - 128, 64, 48, 32, 24 y 16 px como DIB de 32 bpp + mascara AND. El shell de
    Windows pide estos tamanos para el Explorador, la barra de titulo y la barra
    de tareas; ademas, herramientas basadas en GDI+/System.Drawing no saben leer
    frames PNG dentro de un .ico, asi que los tamanos pequenos van en DIB.

No necesita dependencias externas: usa System.Drawing de .NET Framework.
Los textos se escriben sin acentos para que el script se ejecute igual en
consolas con codificacion ANSI (PowerShell 5.1).

.EXAMPLE
powershell -ExecutionPolicy Bypass -File tool\generar_icono.ps1
#>
[CmdletBinding()]
param(
    [string]$Origen,
    [string]$Destino,
    [int[]]$Tamanos = @(256, 128, 64, 48, 32, 24, 16),
    [string]$Respaldo
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Las rutas se resuelven aqui y no en los valores por defecto de param(), porque
# $PSScriptRoot no esta disponible al enlazar los parametros.
$carpetaScript = $PSScriptRoot
if (-not $carpetaScript) { $carpetaScript = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Origen) { $Origen = Join-Path $carpetaScript '..\lib\images\icon.png' }
if (-not $Destino) { $Destino = Join-Path $carpetaScript '..\windows\runner\resources\app_icon.ico' }
if (-not $Respaldo) { $Respaldo = Join-Path $carpetaScript 'app_icon_flutter_backup.ico' }

function Get-MarcoDib {
    <# Devuelve un frame DIB de 32 bpp con su mascara AND (formato clasico de .ico). #>
    param([System.Drawing.Bitmap]$Bitmap)

    $lado = $Bitmap.Width
    $rect = New-Object System.Drawing.Rectangle 0, 0, $lado, $lado
    $datos = $Bitmap.LockBits($rect,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = $datos.Stride
        $pixeles = New-Object byte[] ($stride * $lado)
        [System.Runtime.InteropServices.Marshal]::Copy($datos.Scan0, $pixeles, 0, $pixeles.Length)
    }
    finally {
        $Bitmap.UnlockBits($datos)
    }

    $bytesFilaMascara = [int][Math]::Floor(($lado + 31) / 32) * 4
    $salida = New-Object System.IO.MemoryStream
    $escritor = New-Object System.IO.BinaryWriter $salida

    # BITMAPINFOHEADER. biHeight va duplicado porque el DIB del .ico incluye la
    # mascara AND despues de los pixeles.
    $escritor.Write([int]40)                    # biSize
    $escritor.Write([int]$lado)                 # biWidth
    $escritor.Write([int]($lado * 2))           # biHeight
    $escritor.Write([int16]1)                   # biPlanes
    $escritor.Write([int16]32)                  # biBitCount
    $escritor.Write([int]0)                     # biCompression = BI_RGB
    $escritor.Write([int]($lado * $lado * 4))   # biSizeImage
    $escritor.Write([int]0)                     # biXPelsPerMeter
    $escritor.Write([int]0)                     # biYPelsPerMeter
    $escritor.Write([int]0)                     # biClrUsed
    $escritor.Write([int]0)                     # biClrImportant

    # Pixeles BGRA de abajo hacia arriba, como espera el formato DIB.
    for ($y = $lado - 1; $y -ge 0; $y--) {
        $escritor.Write($pixeles, $y * $stride, $lado * 4)
    }

    # Mascara AND: bit a 1 = transparente (alpha == 0), filas de abajo hacia arriba.
    $mascara = New-Object byte[] ($bytesFilaMascara * $lado)
    for ($y = 0; $y -lt $lado; $y++) {
        $fila = ($lado - 1 - $y) * $bytesFilaMascara
        for ($x = 0; $x -lt $lado; $x++) {
            if ($pixeles[$y * $stride + $x * 4 + 3] -eq 0) {
                $indice = $fila + [int][Math]::Floor($x / 8)
                $mascara[$indice] = $mascara[$indice] -bor (1 -shl (7 - ($x % 8)))
            }
        }
    }
    $escritor.Write($mascara, 0, $mascara.Length)

    $escritor.Flush()
    $resultado = $salida.ToArray()
    $escritor.Dispose()
    $salida.Dispose()
    return , $resultado
}

function Get-MarcoPng {
    param([System.Drawing.Bitmap]$Bitmap)

    $salida = New-Object System.IO.MemoryStream
    $Bitmap.Save($salida, [System.Drawing.Imaging.ImageFormat]::Png)
    $resultado = $salida.ToArray()
    $salida.Dispose()
    return , $resultado
}

function Test-Icono {
    <# Relee el .ico generado y valida cabecera, dimensiones y offsets de cada frame. #>
    param([byte[]]$Bytes, [int[]]$Esperados)

    if ($Bytes.Length -lt 6) { throw 'El .ico generado es demasiado corto.' }
    $reservado = [System.BitConverter]::ToUInt16($Bytes, 0)
    $tipo = [System.BitConverter]::ToUInt16($Bytes, 2)
    $cantidad = [System.BitConverter]::ToUInt16($Bytes, 4)
    if ($reservado -ne 0 -or $tipo -ne 1) { throw "Cabecera de .ico invalida (tipo $tipo)." }
    if ($cantidad -ne $Esperados.Count) {
        throw "Se esperaban $($Esperados.Count) frames y el archivo declara $cantidad."
    }

    $resumen = @()
    for ($i = 0; $i -lt $cantidad; $i++) {
        $base = 6 + 16 * $i
        $ancho = [int]$Bytes[$base]
        $alto = [int]$Bytes[$base + 1]
        $bits = [System.BitConverter]::ToUInt16($Bytes, $base + 6)
        $tamano = [System.BitConverter]::ToUInt32($Bytes, $base + 8)
        $offset = [System.BitConverter]::ToUInt32($Bytes, $base + 12)
        if ($ancho -eq 0) { $ancho = 256 }
        if ($alto -eq 0) { $alto = 256 }
        if ($ancho -ne $alto) { throw "El frame $i no es cuadrado ($ancho x $alto)." }
        if ($offset + $tamano -gt $Bytes.Length) { throw "El frame $i apunta fuera del archivo." }
        $esPng = ($Bytes[$offset] -eq 0x89 -and $Bytes[$offset + 1] -eq 0x50)
        $formato = if ($esPng) { 'PNG' } else { 'DIB 32bpp' }
        $resumen += [pscustomobject]@{ Lado = $ancho; Bits = $bits; Formato = $formato; Bytes = $tamano }
    }
    return $resumen
}

function Test-IconoWindows {
    <# Comprueba con la API nativa del shell (LoadImage) que Windows lee cada frame.
       GDI+/System.Drawing no sabe leer frames PNG ni los mayores de 64 px, por eso
       la validacion se hace con la misma API que usa el Explorador. #>
    param([string]$Ruta, [int[]]$Tamanos)

    if (-not ('IconoNativo' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class IconoNativo {
  [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  public static extern IntPtr LoadImage(IntPtr hinst, string name, uint type, int cx, int cy, uint fuLoad);

  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool DestroyIcon(IntPtr hIcon);
}
'@
    }

    foreach ($lado in $Tamanos) {
        # type 1 = IMAGE_ICON, 0x10 = LR_LOADFROMFILE
        $handle = [IconoNativo]::LoadImage([IntPtr]::Zero, $Ruta, 1, $lado, $lado, 0x10)
        if ($handle -eq [IntPtr]::Zero) {
            $error = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Windows no pudo cargar el frame de $lado px (error Win32 $error)."
        }
        [void][IconoNativo]::DestroyIcon($handle)
    }
}

$rutaOrigen = (Resolve-Path -LiteralPath $Origen).Path
$rutaDestino = [System.IO.Path]::GetFullPath($Destino)
$directorioDestino = [System.IO.Path]::GetDirectoryName($rutaDestino)
if (-not (Test-Path -LiteralPath $directorioDestino)) {
    throw "No existe la carpeta destino: $directorioDestino"
}

if ((Test-Path -LiteralPath $rutaDestino) -and -not (Test-Path -LiteralPath $Respaldo)) {
    Copy-Item -LiteralPath $rutaDestino -Destination $Respaldo
    Write-Host "Respaldo del icono anterior -> $Respaldo"
}

$imagen = [System.Drawing.Image]::FromFile($rutaOrigen)
try {
    Write-Host "Origen : $rutaOrigen ($($imagen.Width)x$($imagen.Height))"
    if ($imagen.Width -ne $imagen.Height) {
        throw "El PNG de origen debe ser cuadrado; mide $($imagen.Width)x$($imagen.Height)."
    }
    $ladoMaximo = ($Tamanos | Measure-Object -Maximum).Maximum
    if ($imagen.Width -lt $ladoMaximo) {
        Write-Warning "El PNG mide $($imagen.Width) px: los tamanos mayores se escalaran y perderan nitidez."
    }

    $marcos = New-Object System.Collections.ArrayList
    foreach ($lado in ($Tamanos | Sort-Object -Descending)) {
        $bitmap = New-Object System.Drawing.Bitmap $lado, $lado, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $grafico = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $grafico.Clear([System.Drawing.Color]::Transparent)
            $grafico.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $grafico.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $grafico.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $grafico.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $grafico.DrawImage($imagen, 0, 0, $lado, $lado)
        }
        finally {
            $grafico.Dispose()
        }

        # PNG solo para 256 px; el resto en DIB de 32 bpp.
        $datos = if ($lado -ge 256) { Get-MarcoPng -Bitmap $bitmap } else { Get-MarcoDib -Bitmap $bitmap }
        $bitmap.Dispose()
        [void]$marcos.Add([pscustomobject]@{ Lado = $lado; Datos = $datos })
    }
}
finally {
    $imagen.Dispose()
}

# Ensamblado del .ico: ICONDIR + una ICONDIRENTRY por frame + los datos de cada frame.
$salida = New-Object System.IO.MemoryStream
$escritor = New-Object System.IO.BinaryWriter $salida
$escritor.Write([int16]0)                 # reservado
$escritor.Write([int16]1)                 # tipo 1 = icono
$escritor.Write([int16]$marcos.Count)     # numero de imagenes

$offset = 6 + 16 * $marcos.Count
foreach ($marco in $marcos) {
    $dimension = if ($marco.Lado -ge 256) { [byte]0 } else { [byte]$marco.Lado }
    $escritor.Write($dimension)                   # ancho (0 = 256)
    $escritor.Write($dimension)                   # alto (0 = 256)
    $escritor.Write([byte]0)                      # colores de paleta
    $escritor.Write([byte]0)                      # reservado
    $escritor.Write([int16]1)                     # planos
    $escritor.Write([int16]32)                    # bits por pixel
    $escritor.Write([int]$marco.Datos.Length)     # bytes del frame
    $escritor.Write([int]$offset)                 # desplazamiento del frame
    $offset += $marco.Datos.Length
}
foreach ($marco in $marcos) {
    $escritor.Write($marco.Datos, 0, $marco.Datos.Length)
}
$escritor.Flush()
$ico = $salida.ToArray()
$escritor.Dispose()
$salida.Dispose()

$tabla = Test-Icono -Bytes $ico -Esperados $Tamanos
[System.IO.File]::WriteAllBytes($rutaDestino, $ico)
Test-IconoWindows -Ruta $rutaDestino -Tamanos $Tamanos

Write-Host ''
$tabla | Sort-Object Lado -Descending | Format-Table -AutoSize | Out-String | Write-Host
Write-Host ("Icono escrito: {0} ({1:N1} KB, {2} frames)" -f $rutaDestino, ($ico.Length / 1KB), $marcos.Count)
Write-Host 'Recuerda reconstruir el .exe: flutter clean; flutter build windows --release'
