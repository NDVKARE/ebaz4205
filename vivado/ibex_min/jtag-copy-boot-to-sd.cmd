@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0jtag-copy-boot-to-sd.ps1" %*
set "jtag_sd_result=%ERRORLEVEL%"
exit /b %jtag_sd_result%
