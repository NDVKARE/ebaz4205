param(
    [Parameter(Mandatory = $true)][string]$Hdf,
    [Parameter(Mandatory = $true)][string]$Destination
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Hdf).Path)
try {
    foreach ($name in @('ps7_init.c', 'ps7_init.h', 'ibex_ps.hwh')) {
        $entry = $archive.GetEntry($name)
        if ($null -eq $entry) { throw "HDF is missing $name" }
        $inputStream = $entry.Open()
        try {
            $outputStream = [IO.File]::Create((Join-Path $Destination $name))
            try { $inputStream.CopyTo($outputStream) }
            finally { $outputStream.Dispose() }
        } finally { $inputStream.Dispose() }
    }
} finally { $archive.Dispose() }
