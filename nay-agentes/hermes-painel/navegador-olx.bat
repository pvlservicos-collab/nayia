@echo off
rem Navegador do Agente OLX: de dois cliques. Liga ESCONDIDO (nenhuma janela): o Chrome do agente aparece e se
rem controla pela tela do admin (Agentes > Agente OLX). Outros usos: navegador-olx.bat mostrar | esconder | desligar
if "%~1"=="" (
  start "" /min powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0navegador-olx.ps1" ligar
) else (
  powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0navegador-olx.ps1" %1
)
