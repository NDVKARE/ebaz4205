@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0copy-boot-to-sd.ps1" %*
set "boot_copy_result=%ERRORLEVEL%"
exit /b %boot_copy_result%
