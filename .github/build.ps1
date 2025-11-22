# load env vars
. C:\Users\Administrator\repo\$env:REMOTE_REPO_SUBDIR"\envvars.ps1
ls
Write-Host "🔨 Building project..."
cd "C:\Users\Administrator\repo\$env:REMOTE_REPO_SUBDIR"
ls
.\mvnw.cmd clean package -Pnative "-Dmaven.test.skip=true"

Write-Host "🔍 Checking artifact..."
$artifact = "C:\Users\Administrator\repo\$env:REMOTE_REPO_SUBDIR\$env:BUILD_DIR\$env:ARTIFACT_NAME$env:ARTIFACT_EXT"

if (!(Test-Path $artifact)) {
    Write-Error "Artifact NOT found at $artifact"
    exit 1
}

Write-Host "📁 Ensuring output/ exists..."
New-Item -ItemType Directory -Force -Path "C:\Users\Administrator\output" | Out-Null

Write-Host "📦 Copying..."
Copy-Item $artifact "C:\Users\Administrator\output" -Force

Write-Host "🎉 Build script done"
