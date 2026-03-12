@echo off
setlocal
py -3 "%~dp0dope" %*
if errorlevel 9009 python "%~dp0dope" %*
