#ps1_sysnative

## 1. Globale Variablen & Pfade
$ErrorActionPreference = "Stop"

$localUserPassword = ConvertTo-SecureString -AsPlainText -Force "Passw0rd"

$Paths = @{
    Dsc  = "C:\DSC"
    Temp = "C:\Temp"
    Logs = "C:\DSC\Logs"
}

$Paths.Values | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

$Zips = @{
    Git = @{
        Url        = "https://git.itsbw.cir/openstack/dsc.test/archive/main.zip"
        Headers    = @{ Authorization = "Bearer xxx" }
        DestDir    = "C:\Temp\git"
        MoveToRoot = $Paths.Dsc
    }
    DSC = @{
        Url        = "https://git.itsbw.cir/openstack/dsc.test/releases/download/v1.0.0/DSC-3.1.3-x86_64-pc-windows-msvc.zip"
        Headers    = @{ Authorization = "Bearer xxx" }
        DestDir    = "C:\DSC\tools\DSC3"
        MoveToRoot = $null
    }
    PowerShell = @{
        Url        = "https://git.itsbw.cir/openstack/dsc.test/releases/download/v1.0.0/PowerShell-7.6.0-win-x64.zip"
        Headers    = @{ Authorization = "Bearer xxx" }
        DestDir    = "C:\DSC\tools\PowerShell7"
        MoveToRoot = $null
    }
}

function Enable-TrustAllCerts {
    if (-not ("TrustAllCertsPolicy" -as [type])) {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;

public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint,
        X509Certificate certificate,
        WebRequest request,
        int certificateProblem
    ) {
        return true;
    }
}
"@
    }

    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

function Invoke-WebArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$DestDir,

        [hashtable]$Headers = $null,

        [string]$TempDir = "C:\Temp",

        [string]$MoveToRoot = $null
    )

    if (-not (Test-Path $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    }

    if (Test-Path $DestDir) {
        Remove-Item -Path $DestDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null

    if ($MoveToRoot) {
        if (-not (Test-Path $MoveToRoot)) {
            New-Item -ItemType Directory -Path $MoveToRoot -Force | Out-Null
        }
    }

    $fileName = Split-Path $Url -Leaf
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        throw "Aus der URL konnte kein Dateiname ermittelt werden: $Url"
    }

    $zipPath = Join-Path $TempDir $fileName

    Write-Output "Download: $Url"
    Invoke-WebRequest `
        -Uri $Url `
        -Headers $Headers `
        -OutFile $zipPath `
        -UseBasicParsing `
        -ErrorAction Stop

    Write-Output "Extract: $zipPath -> $DestDir"
    Expand-Archive `
        -Path $zipPath `
        -DestinationPath $DestDir `
        -Force `
        -ErrorAction Stop

    if ($MoveToRoot) {
        $subFolders = @(Get-ChildItem -Path $DestDir -Directory)

        if ($subFolders.Count -ne 1) {
            throw "Erwartet genau einen Unterordner nach dem Entpacken in '$DestDir', gefunden: $($subFolders.Count)"
        }

        $archiveRoot = $subFolders[0].FullName

        Write-Output "Verschiebe Inhalt von '$archiveRoot' nach '$MoveToRoot'"

        Get-ChildItem -Path $archiveRoot -Force | ForEach-Object {
            Move-Item -Path $_.FullName -Destination $MoveToRoot -Force
        }

        Remove-Item -Path $archiveRoot -Recurse -Force
    }

    return $zipPath
}

### Beginn

Start-Transcript -Path "C:\DSC\Logs\bootstrap.log" -Force

## 2. Lokaler Admin
Set-LocalUser -Name "Administrator" -Password $localUserPassword -ErrorAction Stop
Write-Output "Local Administrator password updated."

## 3. Downloads
Enable-TrustAllCerts

foreach ($name in $Zips.Keys) {
    $zip = $Zips[$name]

    Write-Output "Verarbeite: $name"

    Invoke-WebArchive `
        -Url $zip.Url `
        -Headers $zip.Headers `
        -DestDir $zip.DestDir `
        -TempDir $Paths.Temp `
        -MoveToRoot $zip.MoveToRoot
}

# 4. Path Variable
$pathAdd = @("C:\DSC\tools\PowerShell7", "C:\DSC\tools\DSC3")
$currentPathArray = [Environment]::GetEnvironmentVariable("Path", "Machine") -split ";"
$newPathArray = ($currentPathArray + $pathAdd) | Where-Object { $_ } | Select-Object -Unique
$currentPathString = $newPathArray -join ";"
[Environment]::SetEnvironmentVariable("Path", $currentPathString, "Machine")
$env:Path = $currentPathString
Write-Output "SUCCESS: System Path updated. Current Path: $env:Path"

# 5. PSModules
$modulePath = "C:\DSC\PSModules"
$current = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine")
if ($current -notlike "*$modulePath*") {
    $newPath = "$modulePath;$current"
    [Environment]::SetEnvironmentVariable("PSModulePath", $newPath, "Machine")
}
$env:PSModulePath = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine")

# 5a. Alte DSC Konfiuration löschen
Write-Output "Cleaning up old DSC configurations..."
$stages = @("Current", "Pending", "Previous")
foreach ($stage in $stages) {
    Write-Output "Removing DSC Stage: $stage"
    # 2>&1 stellt sicher, dass auch Fehler im Transcript landen
    powershell -NoLogo -Command "Remove-DscConfigurationDocument -Stage $stage -Force" 2>&1
}
Write-Output "DSC cleanup completed."

# 6. DSC starten
Write-Output "Starting dsc.ps1..."
Set-Location $Paths.Dsc 
powershell -NoLogo -Command ("& {0}\dsc.ps1" -f $Paths.Dsc)

Stop-Transcript
