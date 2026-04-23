$ErrorActionPreference = "Stop"
. .env.ps1

$paths = (Get-ChildItem $GlobalConfig.Paths.DscRoot\components).FullName

foreach ($path in $paths){
    Write-Output "Starte DSC mit: $path"
    dsc config set --file $path
}
