@echo off
setlocal enabledelayedexpansion

echo ============================================================
echo   DisplayMac Android Client Deployment Script
echo ============================================================

set ADB="%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not exist %ADB% (
    where adb >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        set ADB=adb
    ) else (
        echo [ERROR] adb.exe not found. Ensure Android SDK is installed.
        exit /b 1
    )
)

echo [1/3] Checking connected Android devices...
%ADB% devices

echo [2/3] Setting up USB Port Forwarding (7100, 7101)...
%ADB% reverse tcp:7100 tcp:7100
%ADB% reverse tcp:7101 tcp:7101

echo [3/3] Building and Installing APK via Gradle...
cd "%~dp0..\android-client"
call gradlew.bat assembleDebug

if exist "app\build\outputs\apk\debug\app-debug.apk" (
    echo Installing app-debug.apk on connected tablet...
    %ADB% install -r "app\build\outputs\apk\debug\app-debug.apk"
    echo Launching DisplayMac...
    %ADB% shell am start -n com.displaymac.client/.MainActivity
    echo [DONE] DisplayMac is running on your Samsung Tab!
) else (
    echo [NOTE] Build finished or Gradle not run. Open android-client in Android Studio to build.
)

pause
