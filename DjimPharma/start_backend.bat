@echo off
title DjimPharma Backend (Django)
color 0A

echo ========================================================
echo         DEMARRAGE DU BACKEND DJIMPHARMA (DJANGO)
echo ========================================================
echo.

:: Se positionner dans le dossier DjimPharma
cd /d "C:\Users\hp\Desktop\Djimpharma\DjimPharma"

:: Verification de l'environnement virtuel
if not exist ".venv\Scripts\python.exe" (
    color 0C
    echo [ERREUR] L'environnement virtuel .venv est introuvable dans :
    echo %cd%
    echo.
    pause
    exit /b 1
)

:: Configuration automatique de la redirection ADB (si telephone connecte par USB)
where adb >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [*] Configuration du tunnel USB ADB vers le port 8000...
    adb reverse tcp:8000 tcp:8000 >nul 2>&1
) else (
    if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
        echo [*] Configuration du tunnel USB ADB vers le port 8000...
        "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" reverse tcp:8000 tcp:8000 >nul 2>&1
    )
)

echo.
echo [*] Lancement du serveur Django sur http://0.0.0.0:8000/ ...
echo [*] Pour arreter le serveur : faites Ctrl + C
echo.
echo ========================================================
echo.

:: Lancement du serveur Django
".venv\Scripts\python.exe" manage.py runserver 0.0.0.0:8000

if %ERRORLEVEL% neq 0 (
    echo.
    color 0C
    echo [ERREUR] Le serveur s'est arrete avec une erreur.
    pause
)
