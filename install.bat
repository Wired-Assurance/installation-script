@echo off
REM APISphere WAF Installation Script for Windows
REM Enhanced with port conflict resolution

echo [SETUP] APISphere WAF Installation Starting...
echo.

if "%~2"=="" (
    echo [ERROR] Usage: install.bat PLATFORM_ID BACKEND_PORT [WAF_PORT]
    echo.
    echo Examples:
    echo   install.bat my-cool-project-uuid 8000
    echo   install.bat my-cool-project-uuid 3000 9080
    echo   install.bat my-cool-project-uuid 5000 8080
    echo.
    echo Arguments:
    echo   PLATFORM_ID   - Your project UUID
    echo   BACKEND_PORT - Port where your application is currently running
    echo   WAF_PORT     - Port for WAF-protected access ^(optional, default: 8080^)
    echo.
    echo Description:
    echo   Your app runs on BACKEND_PORT, WAF will run on WAF_PORT ^(default 8080^)
    echo   Users access your protected app via WAF_PORT
    exit /b 1
)

set PLATFORM_ID=%~1
set BACKEND_PORT=%~2
if "%~3"=="" (set WAF_PORT=8080) else (set WAF_PORT=%~3)



echo [CONFIG] Configuration:
echo   Platform ID: %PLATFORM_ID%
echo   Your app runs on: %BACKEND_PORT%
echo   WAF will run on: %WAF_PORT%
echo.

echo [CHECK] Verifying Docker availability...
docker --version >nul 2>&1
if errorlevel 1 (
    echo [WARN] Docker is not installed or not available in PATH.
    echo [INSTALL] Attempting to install Docker Desktop...
    
    REM Check if we have admin privileges
    net session >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Docker installation requires administrator privileges.
        echo [ACTION] Please run this script as Administrator or install Docker Desktop manually:
        echo          https://www.docker.com/products/docker-desktop
        exit /b 1
    )
    
    REM Download and install Docker Desktop
    echo [DOWNLOAD] Downloading Docker Desktop installer...
    powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://desktop.docker.com/win/main/amd64/Docker%%20Desktop%%20Installer.exe' -OutFile 'DockerDesktopInstaller.exe'}"
    
    if not exist "DockerDesktopInstaller.exe" (
        echo [ERROR] Failed to download Docker Desktop installer.
        echo [TIP]  Please install Docker Desktop manually from https://www.docker.com/products/docker-desktop
        exit /b 1
    )
    
    echo [INSTALL] Installing Docker Desktop... This may take several minutes.
    "DockerDesktopInstaller.exe" install --quiet --accept-license
    
    if errorlevel 1 (
        echo [ERROR] Docker Desktop installation failed.
        echo [TIP]  Please install Docker Desktop manually from https://www.docker.com/products/docker-desktop
        del "DockerDesktopInstaller.exe" >nul 2>&1
        exit /b 1
    )
    
    del "DockerDesktopInstaller.exe" >nul 2>&1
    echo [OK] Docker Desktop installed successfully.
    echo [INFO] Please restart this script after Docker Desktop has fully started.
    echo [INFO] You may need to restart your computer for Docker to work properly.
    exit /b 0
)
echo [OK] Docker is available

echo [CHECK] Verifying Docker status...
docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not running. Please start Docker Desktop and try again.
    exit /b 1
)
echo [OK] Docker is running

echo [VOLUME] Creating persistent storage for project ID...
docker volume create apisphere-config-%PLATFORM_ID% >nul 2>&1

REM Store in Docker volume with proper permissions
echo %PLATFORM_ID% > temp_id
docker run --rm -i -v apisphere-config-%PLATFORM_ID%:/config busybox sh -c "cat > /config/PLATFORM_ID && chmod 644 /config/PLATFORM_ID" < temp_id
del temp_id

REM Store WAF_PORT in Docker volume
echo %WAF_PORT% > temp_waf
docker run --rm -i -v apisphere-config-%PLATFORM_ID%:/config busybox sh -c "cat > /config/WAF_PORT && chmod 644 /config/WAF_PORT" < temp_waf
del temp_waf

REM Verify storage
docker run --rm -v apisphere-config-%PLATFORM_ID%:/config busybox sh -c "ls -l /config && cat /config/PLATFORM_ID"

if errorlevel 1 (
    echo [ERROR] Failed to store PLATFORM_ID in Docker volume
    exit /b 1
)
echo [OK] Project ID stored securely in Docker volume

echo [PULL] Downloading APISphere WAF image...
REM Public ECR repository URL format: public.ecr.aws/[registry-alias]/[repository-name]:[tag]
REM Private ECR repository URL format: [aws-account-id].dkr.ecr.[region].amazonaws.com/[repository-name]:[tag]

REM Replace with your actual ECR repository URL
set ECR_REPO=public.ecr.aws/u2u6i4x5/waf-image
set IMAGE_TAG=latest

docker pull %ECR_REPO%:%IMAGE_TAG% >nul
if errorlevel 1 (
    echo [ERROR] Image download failed. Check network connection
    echo [TIP]  Try manual pull: docker pull %ECR_REPO%:%IMAGE_TAG%
    exit /b 1
)
echo [OK] Image downloaded successfully from Amazon ECR

echo [CHECK] Verifying backend on port %BACKEND_PORT%...
set SERVICE_RUNNING=false
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%BACKEND_PORT%"') do (
    tasklist /FI "PID eq %%a" | findstr /i "java node python" >nul && set SERVICE_RUNNING=true
)

if "%SERVICE_RUNNING%"=="false" (
    echo [ERROR] No valid service detected on port %BACKEND_PORT%
    echo [TIP]  1. Ensure your app is running before installation
    echo        2. Confirm port matches your app configuration
    echo        3. Check for firewall blocking
    exit /b 1
)
echo [OK] Backend service confirmed

REM Check for port conflicts and resolve
echo [PORT] Checking port availability...
set PORT_CONFLICT=false
netstat -ano | findstr ":%WAF_PORT% " >nul && set PORT_CONFLICT=true
docker ps --format "{{.Ports}}" | findstr ":%WAF_PORT%" >nul && set PORT_CONFLICT=true

if "%PORT_CONFLICT%"=="true" (
    echo [WARN] Port %WAF_PORT% is already in use
    echo [RESOLVE] Attempting to resolve port conflict...
    
    REM Find and stop conflicting containers
    for /f "tokens=1" %%i in ('docker ps --format "{{.ID}} {{.Ports}}" ^| findstr ":%WAF_PORT%"') do (
        echo [CLEANUP] Stopping conflicting container: %%i
        docker stop %%i >nul 2>&1
        docker rm %%i >nul 2>&1
    )
    
    REM Verify port is now available
    netstat -ano | findstr ":%WAF_PORT% " >nul && (
        echo [ERROR] Port %WAF_PORT% still in use after cleanup
        echo [TIP]  1. Close applications using port %WAF_PORT%
        echo        2. Choose a different WAF_PORT
        echo        3. Run: netstat -ano | findstr ":%WAF_PORT%"
        exit /b 1
    )
    echo [OK] Port conflict resolved
)

echo [CLEANUP] Removing old containers...
docker rm -f apisphere-waf-%PLATFORM_ID% >nul 2>&1



echo [START] Launching WAF protection...
docker run -d --name apisphere-waf-%PLATFORM_ID% ^
    -v apisphere-config-%PLATFORM_ID%:/app/config:ro ^
    -e PLATFORM_ID=%PLATFORM_ID% ^
    -e BACKEND_PORT=%BACKEND_PORT% ^
    -e WAF_PORT=%WAF_PORT% ^
    -p %WAF_PORT%:%WAF_PORT% ^
    %ECR_REPO%:%IMAGE_TAG%


echo [STATUS] Waiting for container initialization (5 seconds)...
timeout /t 5 /nobreak >nul

REM Verify PLATFORM_ID inside the running container
docker exec apisphere-waf-%PLATFORM_ID% ls -l /app/config
docker exec apisphere-waf-%PLATFORM_ID% cat /app/config/PLATFORM_ID

if errorlevel 1 (
    echo [ERROR] Failed to start WAF container
    exit /b 1
)

echo [OK] APISphere WAF started successfully
echo.
echo [SUCCESS] Installation Complete!
echo.
echo [PERSISTENCE] Platform ID stored in Docker volume:
echo   Volume Name: apisphere-config-%PLATFORM_ID%
echo   Mount Point: /app/config (read-only in container)
echo.
echo [ENDPOINTS]
echo   Direct backend: http://localhost:%BACKEND_PORT%
echo   WAF-protected:  http://localhost:%WAF_PORT%
echo.
echo [TEST] Verify WAF operation:
echo   curl -v http://localhost:%WAF_PORT%/
echo   curl -v http://localhost:%WAF_PORT%/ --header "X-Test-Header: testvalue"
echo.
echo [NOTE] Allow 1-2 minutes for full initialization