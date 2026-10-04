param(
    [string]$Source = (Join-Path $PSScriptRoot 'BOOT-PETALINUX-IBEX.BIN'),
    [string]$Xsdb = 'D:\Xilinx\SDK\2015.1\bin\xsdb.bat'
)

$ErrorActionPreference = 'Stop'
$dataAddress = 0x08000000
$descriptorAddress = 0x07fff000
$maximumSize = 32MB

Add-Type -TypeDefinition @'
public static class EbazCrc32 {
    public static uint Compute(byte[] data) {
        uint crc = 0xffffffffU;
        foreach (byte value in data) {
            crc ^= value;
            for (int bit = 0; bit < 8; bit++)
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320U : crc >> 1;
        }
        return crc ^ 0xffffffffU;
    }
}
'@

try {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Khong tim thay anh boot: $Source"
    }
    if (-not (Test-Path -LiteralPath $Xsdb -PathType Leaf)) {
        throw "Khong tim thay XSDB: $Xsdb"
    }
    $sourcePath = (Resolve-Path -LiteralPath $Source).Path
    $image = [IO.File]::ReadAllBytes($sourcePath)
    if ($image.Length -eq 0 -or $image.Length -gt $maximumSize) {
        throw "Kich thuoc BOOT.BIN phai tu 1 den $maximumSize byte."
    }
    $crc = [EbazCrc32]::Compute($image)
    $sha = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    Write-Host 'Tren UART U-Boot phai dang hien: JTAG-SD: waiting ...'
    Write-Host ("Dang nap {0} byte qua JTAG, CRC32={1:x8}" -f $image.Length, $crc)

    $xsdbOutput = @(& $Xsdb -q -s (Join-Path $PSScriptRoot 'jtag-copy-boot-to-sd.tcl') `
        $sourcePath ('0x{0:x8}' -f $dataAddress) `
        ('0x{0:x8}' -f $descriptorAddress) $image.Length ('0x{0:x8}' -f $crc) 2>&1)
    $xsdbOutput | ForEach-Object { Write-Host $_ }
    $successMarker = $xsdbOutput | Select-String -SimpleMatch 'JTAG transfer complete:'
    if ($LASTEXITCODE -or -not $successMarker) {
        throw "XSDB khong xac nhan truyen thanh cong (ma loi $LASTEXITCODE)."
    }

    Write-Host 'Da gui xong qua JTAG. Xem UART de cho U-Boot kiem tra va ghi SD.' -ForegroundColor Green
    Write-Host "SHA256 file nguon: $sha"
    exit 0
} catch {
    Write-Host "LOI: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
