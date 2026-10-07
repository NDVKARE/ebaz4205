param(
    [string]$Port = 'COM5',
    [string]$File = (Join-Path $PSScriptRoot '../vivado/ibex_min/pmufw.bin'),
    [int]$Baud = 115200
)
$ErrorActionPreference = 'Stop'
$payload = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $File).Path)
if ($payload.Length -lt 1 -or $payload.Length -gt 16384) { throw 'Firmware must be 1..16384 bytes.' }

function Wait-Byte([int[]]$Values, [int]$Seconds = 20) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $value = $serial.ReadByte() } catch [TimeoutException] { continue }
        if ($value -eq 24) { throw 'Receiver cancelled transfer.' }
        if ($Values -contains $value) { return $value }
    }
    throw 'Timed out waiting for U-Boot YMODEM response.'
}

function Make-Packet([int]$Number, [byte[]]$Data) {
    $packet = New-Object byte[] ($Data.Length + 5)
    $packet[0] = 1 # SOH: 128-byte block
    $packet[1] = $Number -band 255
    $packet[2] = 255 - $packet[1]
    [Array]::Copy($Data, 0, $packet, 3, $Data.Length)
    $crc = 0
    foreach ($b in $Data) {
        $crc = $crc -bxor ([int]$b -shl 8)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if ($crc -band 0x8000) { $crc = (($crc -shl 1) -bxor 0x1021) -band 0xffff }
            else { $crc = ($crc -shl 1) -band 0xffff }
        }
    }
    $packet[$packet.Length-2] = $crc -shr 8
    $packet[$packet.Length-1] = $crc -band 255
    return ,$packet
}

function Send-Packet([byte[]]$Packet) {
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $serial.Write($Packet, 0, $Packet.Length)
        if ((Wait-Byte @(6,21)) -eq 6) { return }
    }
    throw 'Too many YMODEM retries.'
}

$serial = New-Object IO.Ports.SerialPort($Port, $Baud, [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
$serial.Handshake = [IO.Ports.Handshake]::None
$serial.ReadTimeout = 1000
$serial.WriteTimeout = 10000
$serial.NewLine = "`n"
try {
    $serial.Open()
    $serial.DiscardInBuffer()
    # Board must already be stopped at the U-Boot prompt.
    $serial.Write("loady 0x08000000 $Baud`r")
    $ready = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $line = $serial.ReadLine() } catch [TimeoutException] { continue }
        Write-Host $line.TrimEnd()
        if ($line -like '*Ready for binary*ymodem*') { $ready = $true; break }
    }
    if (-not $ready) { throw 'No YMODEM prompt. Stop autoboot in U-Boot before running this script.' }
    $null = Wait-Byte @(67)
    $header = New-Object byte[] 128
    $metadata = [Text.Encoding]::ASCII.GetBytes("pmufw.bin" + [char]0 + $payload.Length.ToString() + [char]0)
    [Array]::Copy($metadata, $header, $metadata.Length)
    Send-Packet (Make-Packet 0 $header)
    $null = Wait-Byte @(67)
    $block = 1
    for ($offset = 0; $offset -lt $payload.Length; $offset += 128) {
        $data = New-Object byte[] 128
        [Array]::Copy($payload, $offset, $data, 0, [Math]::Min(128, $payload.Length-$offset))
        Send-Packet (Make-Packet $block $data)
        $block++
    }
    $eot = [byte[]]@(4)
    $serial.Write($eot, 0, 1)
    if ((Wait-Byte @(6,21)) -eq 21) {
        $serial.Write($eot, 0, 1)
        $null = Wait-Byte @(6)
    }
    $null = Wait-Byte @(67)
    Send-Packet (Make-Packet 0 (New-Object byte[] 128))
    Write-Host "Sent $($payload.Length) bytes to U-Boot RAM. SD has not been written."
    Write-Host 'Reconnect your serial terminal, then run:'
    Write-Host 'fatwrite mmc 0:1 0x08000000 pmufw.bin ${filesize}'
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
