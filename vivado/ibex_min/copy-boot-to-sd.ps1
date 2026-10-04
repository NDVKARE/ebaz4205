param(
    # Default to the current PMU GPIO image; the SD boot filename is BOOT.BIN.
    [string]$Source = (Join-Path $PSScriptRoot 'BOOT-GPIO.BIN'),
    [ValidatePattern('^[A-Za-z]:\\?$')]
    [string]$Drive = 'F:'
)

$ErrorActionPreference = 'Stop'

try {
    $sdRoot = $Drive.TrimEnd('\') + '\'
    if (-not (Test-Path -LiteralPath $sdRoot -PathType Container)) {
        throw "Khong tim thay the nho/ o dia $sdRoot. Hay cam the va kiem tra ky tu o dia."
    }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Khong tim thay anh boot: $Source"
    }

    $sourcePath = (Resolve-Path -LiteralPath $Source).Path
    $destination = Join-Path $sdRoot 'BOOT.BIN'
    if ($sourcePath -ieq $destination) {
        throw 'File nguon trung voi file dich BOOT.BIN tren the.'
    }
    $sourceFile = Get-Item -LiteralPath $sourcePath
    if ($sourceFile.Length -eq 0) {
        throw 'Anh boot rong, khong copy.'
    }
    $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash

    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $backupName = 'BOOT.BIN.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        $backupPath = Join-Path $sdRoot $backupName
        Copy-Item -LiteralPath $destination -Destination $backupPath
        Write-Host "Da sao luu: $backupPath"
    }

    Copy-Item -LiteralPath $sourcePath -Destination $destination -Force
    $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($destinationHash -ne $sourceHash) {
        throw 'Kiem tra SHA256 that bai: file tren the khong khop file nguon.'
    }

    Write-Host "THANH CONG: $sourcePath -> $destination" -ForegroundColor Green
    Write-Host "Kich thuoc: $($sourceFile.Length) byte; SHA256: $destinationHash"
    Write-Host 'Hay dung Eject/Safely Remove Hardware truoc khi rut the.'
    exit 0
} catch {
    Write-Host "LOI: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
