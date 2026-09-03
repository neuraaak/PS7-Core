<#
.SYNOPSIS
    Interactive smoke test for Read-FolderSelection (PS7-Core.UI).

.DESCRIPTION
    Creates a scratch folder tree (direct children, an excluded child, and a
    nested child), then calls Read-FolderSelection -Interactive against it so
    you can see the real Spectre checkbox prompt in your own console. Only the
    names of direct, non-excluded children should appear — something that can't
    be verified from a redirected / non-interactive shell.

    Generic by design: Read-FolderSelection has no notion of what a folder is
    for, so this test doesn't either. Use -ExcludeName to try the exclusion
    behavior with names relevant to whichever script you're validating it for.

    The scratch tree is removed afterward unless -KeepTestPath is passed.

.PARAMETER TestPath
    Where to create the scratch tree. Defaults to a new folder under %TEMP%.

.PARAMETER ExcludeName
    Folder names to exclude from the candidates, passed straight to
    Read-FolderSelection. Default: 'excluded-a', 'excluded-b'.

.PARAMETER KeepTestPath
    Do not delete the scratch tree at the end.

.EXAMPLE
    .\Test-ReadFolderSelection.ps1
    Runs the interactive picker against a throwaway temp folder with the
    default sample tree.

.EXAMPLE
    .\Test-ReadFolderSelection.ps1 -ExcludeName 'images', 'videos'
    Same test, but with exclusion names matching a specific caller's use case.
#>

#Requires -Version 7.0

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$TestPath,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeName = @('excluded-a', 'excluded-b'),

    [Parameter(Mandatory = $false)]
    [switch]$KeepTestPath
)

$ErrorActionPreference = 'Stop'

$modulesPath = Split-Path -Parent $PSScriptRoot
if ($env:PSModulePath -notlike "*$modulesPath*") {
    $env:PSModulePath += ";$modulesPath"
}

Import-Module PS7-Core -Force

Assert-PowerShell7
$null = Initialize-EnhancedUI

if (-not $TestPath) {
    $TestPath = Join-Path ([System.IO.Path]::GetTempPath()) "ReadFolderSelection-Test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
}

Write-StatusMessage "Building scratch tree at: $TestPath" -Type Info

New-Item -ItemType Directory -Path $TestPath -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $TestPath 'kept-a') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $TestPath 'kept-b') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $TestPath 'kept-a/nested-child') -Force | Out-Null

foreach ($name in $ExcludeName) {
    New-Item -ItemType Directory -Path (Join-Path $TestPath $name) -Force | Out-Null
}

Write-StatusMessage "Tree ready: kept-a, kept-b, $($ExcludeName -join ', ') (excluded), kept-a/nested-child (not selectable)" -Type Success
Write-Host ""

$selected = @(Read-FolderSelection -Path $TestPath `
        -ExcludeName $ExcludeName `
        -Interactive `
        -Message "Pick folders to keep")

Write-Host ""
Write-Header "Result"

if ($selected.Count -eq 0) {
    Write-StatusMessage "Nothing selected." -Type Warning
}
else {
    foreach ($path in $selected) {
        Write-StatusMessage $path -Type Success
    }
}

if (-not $KeepTestPath) {
    Remove-Item -Path $TestPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-StatusMessage "Scratch tree removed." -Type Info
}
else {
    Write-StatusMessage "Scratch tree kept at: $TestPath" -Type Info
}
