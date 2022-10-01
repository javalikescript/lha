@echo off
:bof
bin\lua lha.lua %*
set STATUS=%ERRORLEVEL%
if %STATUS% equ 11 goto bof
exit /b %STATUS%
