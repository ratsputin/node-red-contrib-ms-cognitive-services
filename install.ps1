if (-not (Test-Path ".\debug\package.json"))
{
    $check = docker container inspect -f '{{.State.Running}}' "nodered_testing"

    if ($check)
    {
       docker-compose down  
    }

    docker-compose up -d   

    Write-Host "Waiting for node-red to boot ..." -NoNewLine 
    while (!(Test-Path ".\debug\package.json")) 
    { 
        Start-Sleep 2
    }
    
    Write-Host -ForegroundColor Green " done"
}

docker-compose down

$origin = [Environment]::CurrentDirectory;
$repoName = $origin.Split('\') | Select-Object -Last 1
Write-Host "Name: $repoName"
if(-not (Test-Path ".\debug\myModules\$repoName"))
{
    Write-Output "Creating Path..."
    New-Item -ItemType Directory ".\debug\myModules\$repoName"
}

$destination = Resolve-Path .\debug\

Write-Output "Copy files..."
$src = Resolve-Path '.\src'

$destRoot = Resolve-Path ".\debug\myModules\$repoName"

Write-Output "From : $src"
Write-Output "To   : $destRoot"

$packageModified = $false 


$files = Get-ChildItem -Recurse ./src | Where-Object { ! $_.PSIsContainer }
foreach($file in $files)
{
    $relativeFile = $file.FullName.Substring($src.Path.Length)
    $dest = Join-Path -Path $destRoot -ChildPath $relativeFile

    if($file.Name -eq "package.json")
    {
        if(Test-Path $dest)
        {
            Write-Output "Comparing package.json ..."
            $packageModified = (Get-FileHash $file.FullName).hash  -ne (Get-FileHash $dest).hash
            if($packageModified)
            {
                Write-Host "package.json was modified. Reinstall again after copy!" -ForegroundColor Red
            }
            else
            {
                Write-Host "Unmodified. No reinstallation needed!" -ForegroundColor Green
            }
        }
        else 
        {
            $packageModified = $true;
        }
    }

    $folder = $dest.Substring(0, $dest.LastIndexOf("\"))
    if(-not (Test-Path $folder))
    {
        New-Item -ItemType Directory $folder
    }

    Write-Output $dest
    [System.IO.File]::Copy($file.FullName, $dest, $true);
}

Write-Output "Change location to: $destination"
Set-Location $destination

if($packageModified)
{
    npm install ".\myModules\$repoName"
}

Write-Output "Switching back to: $origin"
Set-Location $origin

# fix for windwos docker
# windows docker can't handle links so we need to copy the files....
if($IsWindows -or $Env:OS -eq "Windows_NT")
{
    Write-Host "Fixing Windows Docker Problems" -ForegroundColor Red
    Write-Host "Resolve symlink" -ForegroundColor Yellow
    $files = Get-ChildItem "./debug/node_modules/"| Where-Object { $_.Attributes -match "ReparsePoint" }
    
    Write-Host "Updating modules..." -ForegroundColor Yellow
    $files = Get-ChildItem "./debug/node_modules/" -Directory
    foreach ($file in $files) {
        
        $moduleName = $file.FullName.Split("\") | Select-Object -Last 1

        if(Test-Path "./debug/myModules/$moduleName")
        {
            Write-Host "Update module: " -NoNewline -ForegroundColor Magenta
            Write-Host $moduleName
            Remove-Item $file.FullName -Force -Recurse
            Copy-Item -Recurse -Path "./debug/myModules/$moduleName/" -Destination "./debug/node_modules/"
        }

    }
}

docker-compose up -d