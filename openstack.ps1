param(
    [ValidateSet("create", "delete")]
    [string]$Action = "create"
)

$ErrorActionPreference = "Stop"
$envPath = Join-Path $PSScriptRoot "env.ps1"
$bootstrapPath = Join-Path $PSScriptRoot "bootstrap.ps1"

if (-not (Test-Path $envPath)) { throw "env.ps1 fehlt." }
. $envPath

$nodeName = $GlobalConfig.Node.Name
$volumes  = $GlobalConfig.OpenStack.Volumes

if ($Action -eq "create") {
    Write-Host "--- Deployment: $nodeName ---" -ForegroundColor Cyan

    # 1. OS-Volume erstellen (falls nicht vorhanden)
    $osVolumeName = "{0}_os" -f $nodeName.ToLower()
    $bootConfig = $volumes | Where-Object { $_.Name -eq "OS" } | Select-Object -First 1

    Write-Host "Erstelle bootfähiges OS-Volume..."
    openstack volume create `
        --size $bootConfig.Size `
        --image "$($GlobalConfig.OpenStack.Image)" `
        --bootable `
        $osVolumeName

    # Warten, bis das Volume 'available' ist (Wichtig für den Boot-Prozess!)
    Write-Host "Warte auf Volume-Status 'available'..."
    while ((openstack volume show $osVolumeName -f value -c status) -ne "available") {
        Start-Sleep -Seconds 2
    }

    # 2. Block Device Mappings vorbereiten
    # Syntax: <dev_name>=<id>:<type>:<size>:<terminate_on_shutdown>:<boot_index>
    $mappings = @()
    # Das OS-Volume ist das Boot-Device (boot_index=0)
    $mappings += "vda=${osVolumeName}:volume::false:0"

    $deviceIndex = 0
    foreach ($vol in $volumes) {
        if ($vol.Name -eq "OS") { continue }
        
        $letter = [char](98 + $deviceIndex) # vdb, vdc...
        $volName = ("{0}_{1}" -f $nodeName, $vol.Name).ToLower()
        
        Write-Host "Erstelle Daten-Volume: $volName"
        openstack volume create --size $vol.Size $volName
        
        # Daten-Volumes haben keinen Boot-Index (bzw. ungleich 0)
        $mappings += "vd${letter}=${volName}:volume::false"
        $deviceIndex++
    }

    # 3. Port erstellen
    Write-Host "Erstelle Port..."
    openstack port create `
        --network "$($GlobalConfig.Node.NetworkingDsc)" `
        --fixed-ip "ip-address=$($GlobalConfig.Node.IP)" `
        --disable-port-security `
        "$nodeName"

    # 4. Server erstellen
    Write-Host "Erstelle Server..."
    $serverArgs = @(
        "server", "create",
        "--flavor", $GlobalConfig.OpenStack.Flavor,
        "--port", $nodeName,
        "--config-drive", "True",
        "--user-data", $bootstrapPath
    )

    foreach ($m in $mappings) {
        $serverArgs += "--block-device-mapping"
        $serverArgs += $m
    }

    $serverArgs += $nodeName
    & openstack @serverArgs
}
# ==========================================================
# FUNKTION: DELETE
# ==========================================================
elseif ($Action -eq "delete") {
    Write-Host "--- Löschvorgang gestartet für: $nodeName ---" -ForegroundColor Yellow

    # 1. Server löschen
    $server = openstack server list --name "^$nodeName$" -f value -c ID
    if ($server) {
        $confirm = Read-Host "Server '$nodeName' gefunden. Löschen? (y/n)"
        if ($confirm -eq 'y') { openstack server delete $nodeName }
    }

    # 2. Port löschen
    $port = openstack port list --name "$nodeName" -f value -c ID
    if ($port) {
        $confirm = Read-Host "Port '$nodeName' gefunden. Löschen? (y/n)"
        if ($confirm -eq 'y') { openstack port delete $nodeName }
    }

    # 3. Volumes löschen (Sucht nach "{nodeName}_*")
    $searchPattern = "$($nodeName.ToLower())_"
    $volsToDelete = openstack volume list --long -f json | ConvertFrom-Json | Where-Object { $_.Name -like "$searchPattern*" }

    foreach ($vol in $volsToDelete) {
        $confirm = Read-Host "Volume '$($vol.Name)' gefunden. Löschen? (y/n)"
        if ($confirm -eq 'y') { openstack volume delete $vol.ID }
    }
    
    Write-Host "Bereinigung abgeschlossen." -ForegroundColor Green
}
