@echo off
chcp 65001 >nul
title kapi blog - publish
set "PS1=%~dp0publish.ps1"
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -File "%~1"
)