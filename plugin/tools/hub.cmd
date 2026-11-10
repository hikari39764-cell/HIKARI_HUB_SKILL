@echo off
rem HIKARI Production Hub: the agent's tool for reading and writing the hub. See hub.ps1 for the commands.
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0hub.ps1" %*
