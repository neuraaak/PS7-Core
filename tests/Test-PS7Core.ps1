<#
.SYNOPSIS
    Tests automatisés pour PS7-Core.Runtime, PS7-Core.UI et PS7-Core.Crypto.

.DESCRIPTION
    Vérifie le bon fonctionnement de :
      1. Assert-PowerShell7 — no-op sous PS7+, erreur sous une version inférieure.
      2. Initialize-EnhancedUI / Write-StatusMessage / Write-Header /
         Write-ProgressBar — provider Spectre.Console, sortie colorée.
      3. Get-FileHashExtended / Get-StringHash / Test-FileIntegrity — comparés à
         des vecteurs de référence publics, pas à une seconde exécution du code.

    PwshSpectreConsole est requis et n'est plus auto-installé par les scripts ;
    -AutoInstallSpectre installe le module pour le test si absent.

.PARAMETER AutoInstallSpectre
    Installe PwshSpectreConsole si absent, avant de lancer les tests UI.

.PARAMETER OnlyRuntime
    N'exécute que les tests PS7-Core.Runtime.

.PARAMETER OnlyUI
    N'exécute que les tests PS7-Core.UI.

.EXAMPLE
    .\Test-PS7-Core.ps1
    Lance tous les tests.

.EXAMPLE
    .\Test-PS7-Core.ps1 -OnlyRuntime
    Tests du garde PS7 seulement.
#>

#Requires -Version 7.0

[CmdletBinding()]
param (
    [switch]$AutoInstallSpectre,
    [switch]$OnlyRuntime,
    [switch]$OnlyUI,

    # Backend UI a tester. 'Native' force le backend sans dependance meme sur une
    # machine qui a Spectre : c'est ainsi que le chemin natif est couvert.
    [ValidateSet('Auto', 'Spectre', 'Native')]
    [string]$Backend = 'Auto'
)

$ErrorActionPreference = 'Continue'

#region Test framework
################################################################################

$script:TestStats = @{ Pass = 0; Fail = 0; Skip = 0 }
$script:TestFailures = @()

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor Cyan
}

function Test-Case {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )
    Write-Host ("  [{0,-50}]" -f $Name) -NoNewline
    try {
        $result = & $Body
        if ($result -is [string] -and $result -eq 'SKIP') {
            $script:TestStats.Skip++
            Write-Host " SKIP" -ForegroundColor Yellow
        }
        elseif ($result -eq $false) {
            $script:TestStats.Fail++
            $script:TestFailures += $Name
            Write-Host " FAIL" -ForegroundColor Red
        }
        else {
            $script:TestStats.Pass++
            Write-Host " OK"   -ForegroundColor Green
        }
    }
    catch {
        $script:TestStats.Fail++
        $script:TestFailures += "$Name -> $($_.Exception.Message)"
        Write-Host " FAIL" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

#endregion


#region Setup
################################################################################

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulesPath = $repoRoot
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "PS7-Core-Tests-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Write-Host ""
Write-Host "PS7-Core Test Suite" -ForegroundColor Magenta
Write-Host "  PowerShell : $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
Write-Host "  Modules    : $modulesPath"
Write-Host "  Temp dir   : $tempDir"

if ($env:PSModulePath -notlike "*$modulesPath*") {
    $env:PSModulePath += ";$modulesPath"
}

try {
    Import-Module PS7-Core -Force -ErrorAction Stop
}
catch {
    Write-Host "FATAL: cannot load PS7-Core modules: $_" -ForegroundColor Red
    exit 2
}

#endregion


#region PS7-Core.Runtime tests
################################################################################

if (-not $OnlyUI) {
    Write-TestHeader "PS7-Core.Runtime — Assert-PowerShell7"

    Test-Case "no-op when current PS >= minimum" {
        try {
            Assert-PowerShell7 -MinimumVersion '5.0'
            return $true
        }
        catch { return $false }
    }

    Test-Case "no-op with default minimum (7.0) under current session" {
        try {
            Assert-PowerShell7
            return ($PSVersionTable.PSVersion.Major -ge 7)
        }
        catch { return $false }
    }

    Test-Case "throws when current PS < minimum" {
        try {
            Assert-PowerShell7 -MinimumVersion '99.0'
            return $false
        }
        catch {
            return ($_.Exception.Message -match '99\.0')
        }
    }
}

#endregion


#region PS7-Core.Runtime logging tests
################################################################################

if (-not $OnlyUI) {
    Write-TestHeader "PS7-Core.Runtime — Logging"

    Test-Case "no log file before Initialize-Logging" {
        $p = Join-Path $tempDir 'never-created.log'
        Write-Log -Message 'ignored'
        return (-not (Test-Path $p)) -and ((Get-LogContext).Enabled -eq $false)
    }

    Test-Case "Initialize-Logging creates the file and Write-Log appends a line" {
        $p = Join-Path $tempDir 'basic.log'
        Initialize-Logging -Path $p
        Write-Log -Message 'hello world'
        if (-not (Test-Path $p)) { return $false }
        $line = @(Get-Content -Path $p | Where-Object { $_ -ne '' })[-1]
        return ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \[INFO   \] hello world$')
    }

    Test-Case "Get-LogContext reports the active path and level" {
        $p = Join-Path $tempDir 'context.log'
        Initialize-Logging -Path $p -MinimumLevel Debug
        $ctx = Get-LogContext
        return ($ctx.Enabled -eq $true) -and ($ctx.MinimumLevel -eq 'Debug') -and ($ctx.Path -eq $p)
    }

    Test-Case "MinimumLevel filters out lower levels" {
        $p = Join-Path $tempDir 'filter.log'
        Initialize-Logging -Path $p -MinimumLevel Warning
        Write-Log -Message 'dropped' -Level Info
        Write-Log -Message 'kept' -Level Error
        $content = Get-Content -Path $p -Raw
        return ($content -notmatch 'dropped') -and ($content -match 'kept')
    }

    Test-Case "a write failure disables logging instead of throwing" {
        $sub = Join-Path $tempDir 'doomed'
        $p = Join-Path $sub 'ok-then-broken.log'
        Initialize-Logging -Path $p
        Write-Log -Message 'first'
        # Le repertoire parent disparait : l'ecriture suivante ne peut pas aboutir.
        Remove-Item -Path $sub -Recurse -Force
        try {
            Write-Log -Message 'boom' -WarningAction SilentlyContinue
        }
        catch { return $false }
        return ((Get-LogContext).Enabled -eq $false)
    }

    Test-Case "Initialize-Logging throws on an unusable path" {
        try {
            Initialize-Logging -Path 'Z:\no-such-volume\deep\x.log'
            return $false
        }
        catch { return $true }
    }

    Test-Case "PROBE: .UI can resolve Write-Log across the nested boundary" {
        $ui = (Get-Module PS7-Core).NestedModules | Where-Object Name -eq 'PS7-Core.UI'
        if (-not $ui) { return $false }
        $resolved = & $ui { Get-Command Write-Log -ErrorAction SilentlyContinue }
        return ($null -ne $resolved)
    }

    Test-Case "Write-StatusMessage feeds the log with its Type as level" {
        $p = Join-Path $tempDir 'tee.log'
        Initialize-Logging -Path $p
        Write-StatusMessage 'teed message' -Type Warning 6>$null
        $content = Get-Content -Path $p -Raw
        return ($content -match '\[WARNING\] teed message')
    }

    Test-Case "Write-Header feeds the log at Info level" {
        $p = Join-Path $tempDir 'tee-header.log'
        Initialize-Logging -Path $p
        Write-Header 'Section title' 6>$null
        $content = Get-Content -Path $p -Raw
        return ($content -match '\[INFO   \] Section title')
    }

    Test-Case "Write-ProgressBar does NOT feed the log" {
        $p = Join-Path $tempDir 'tee-progress.log'
        Initialize-Logging -Path $p
        Write-ProgressBar -Activity 'Work' -Current 1 -Total 2 6>$null
        Write-ProgressBar -Activity 'Work' -Current 2 -Total 2 -Completed 6>$null
        $content = Get-Content -Path $p -Raw
        return ($content -notmatch 'Work')
    }

    Test-Case "the tee stays silent once logging has disabled itself" {
        $sub = Join-Path $tempDir 'tee-doomed'
        $p = Join-Path $sub 'off.log'
        Initialize-Logging -Path $p
        Remove-Item -Path $sub -Recurse -Force
        try {
            Write-StatusMessage 'no crash' -Type Info -WarningAction SilentlyContinue 6>$null
            return ((Get-LogContext).Enabled -eq $false)
        }
        catch { return $false }
    }
}

#endregion


#region PS7-Core.UI tests
################################################################################

if (-not $OnlyRuntime) {
    Write-TestHeader "PS7-Core.UI — Spectre.Console provider and rendering"

    if ($AutoInstallSpectre -and -not (Get-Module -ListAvailable -Name PwshSpectreConsole)) {
        Write-Host "  Installing PwshSpectreConsole (CurrentUser)..." -ForegroundColor Yellow
        try {
            Install-Module -Name PwshSpectreConsole -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop -WarningAction SilentlyContinue
        }
        catch {
            Write-Host "  Install failed: $_" -ForegroundColor Yellow
        }
    }

    $spectreAvailable = [bool](Get-Module -ListAvailable -Name PwshSpectreConsole)

    # Backend effectivement teste dans cette passe.
    $script:TargetBackend = switch ($Backend) {
        'Native' { 'Native' }
        'Spectre' { 'Spectre' }
        default { if ($spectreAvailable) { 'Spectre' } else { 'Native' } }
    }
    $script:IsSpectreRun = ($script:TargetBackend -eq 'Spectre')

    Write-Host "  Backend teste : $($script:TargetBackend)" -ForegroundColor DarkGray

    if ($script:IsSpectreRun -and -not $spectreAvailable) {
        Write-Host "  PwshSpectreConsole not installed — UI tests skipped. Run with -AutoInstallSpectre, or -Backend Native." -ForegroundColor Yellow
    }
    else {
        Test-Case "Initialize-EnhancedUI returns initialized context" {
            $ctx = Initialize-EnhancedUI -Backend $script:TargetBackend
            return ($ctx -and $ctx.Initialized -eq $true -and $ctx.Backend -eq $script:TargetBackend)
        }

        Test-Case "Initialize-EnhancedUI -Backend Spectre throws when Spectre is missing" {
            if ($spectreAvailable) { return 'SKIP' }
            try {
                Initialize-EnhancedUI -Backend Spectre | Out-Null
                return "aucune erreur levee"
            }
            catch { return $true }
        }

        Test-Case "le backend natif reste selectionnable meme avec Spectre installe" {
            $ctx = Initialize-EnhancedUI -Backend Native
            $ok = ($ctx.Backend -eq 'Native') -and ($ctx.UseSpectreConsole -eq $false)
            $null = Initialize-EnhancedUI -Backend $script:TargetBackend
            return $ok
        }

        # For color tests we shadow Write-SpectreHost with a capturing stub so we
        # can assert on exactly what the module passed to the renderer.
        $script:UICapture = [System.Collections.Generic.List[string]]::new()

        function global:Write-SpectreHost { param([string]$s) $script:UICapture.Add($s) }

        Test-Case "Write-StatusMessage Success uses color markup" {
            if (-not $script:IsSpectreRun) { return 'SKIP' }
            $script:UICapture.Clear()
            Write-StatusMessage 'integration-success' -Type Success
            $line = $script:UICapture -join "`n"
            return ($line -match '(?i)\[green\]') -and ($line -match 'integration-success')
        }

        Test-Case "Write-StatusMessage Error uses color markup" {
            if (-not $script:IsSpectreRun) { return 'SKIP' }
            $script:UICapture.Clear()
            Write-StatusMessage 'integration-error' -Type Error
            $line = $script:UICapture -join "`n"
            return ($line -match '(?i)\[red\]') -and ($line -match 'integration-error')
        }

        Test-Case "Write-StatusMessage escapes brackets in user content" {
            if (-not $script:IsSpectreRun) { return 'SKIP' }
            $script:UICapture.Clear()
            Write-StatusMessage 'value=[42]' -Type Info
            $line = $script:UICapture -join "`n"
            # Spectre markup escape: '[' -> '[[', ']' -> ']]'
            return ($line -match '\[\[42\]\]')
        }

        Test-Case "Write-Header does not throw" {
            try { Write-Header 'Test Header'; return $true }
            catch { return $false }
        }

        Test-Case "Write-ProgressBar (intermediate) does not throw" {
            try {
                Write-ProgressBar -Activity 'unit' -Current 1 -Total 10 -Status 'tick'
                Write-ProgressBar -Activity 'unit' -Completed
                return $true
            }
            catch { return $false }
        }

        Test-Case "Write-ProgressBar routes to Spectre inside Start-ProgressScope" {
            if (-not $script:IsSpectreRun) { return 'SKIP' }
            # $script:ProgressTasks / $script:CurrentProgressContext live in the
            # PS7-Core.UI module's own scope, not this script's — a scriptblock
            # literal here has its own $script: scope. Reach into the module's
            # scope explicitly via the invoke-in-module operator (`& $module {}`).
            $uiModule = (Get-Module PS7-Core).NestedModules | Where-Object Name -eq "PS7-Core.UI"
            $script:sawSpectreTask = $false
            Start-ProgressScope -ScriptBlock {
                Write-ProgressBar -Activity 'scope-unit' -Current 1 -Total 4 -Status 'tick'
                $script:sawSpectreTask = & $uiModule { $script:ProgressTasks.ContainsKey('scope-unit') }
                Write-ProgressBar -Activity 'scope-unit' -Completed
            } | Out-Null
            $tasksEmpty = & $uiModule { $script:ProgressTasks.Count -eq 0 }
            $contextNull = & $uiModule { $null -eq $script:CurrentProgressContext }
            return ($script:sawSpectreTask -and $tasksEmpty -and $contextNull)
        }

        Test-Case "Start-ProgressScope does not support nesting" {
            try {
                Start-ProgressScope -ScriptBlock {
                    Start-ProgressScope -ScriptBlock { } | Out-Null
                } | Out-Null
                return $false
            }
            catch {
                return ($_.Exception.Message -match 'nesting')
            }
        }

        Test-Case "Write-StatusMessage inside a scope uses AnsiConsole.MarkupLine, not Write-SpectreHost" {
            if (-not $script:IsSpectreRun) { return 'SKIP' }
            $script:UICapture.Clear()
            Start-ProgressScope -ScriptBlock {
                Write-StatusMessage 'inside-scope' -Type Info
            } | Out-Null
            # If the call had gone through Write-SpectreHost (the outside-scope
            # path), the shadowed stub above would have captured it.
            return ($script:UICapture.Count -eq 0)
        }

        Test-Case "Start-ProgressScope resets module state after the scriptblock throws" {
            $uiModule = (Get-Module PS7-Core).NestedModules | Where-Object Name -eq "PS7-Core.UI"
            try {
                Start-ProgressScope -ScriptBlock {
                    throw 'boom'
                } | Out-Null
            }
            catch { }

            $contextNull = & $uiModule { $null -eq $script:CurrentProgressContext }
            $tasksEmpty = & $uiModule { $script:ProgressTasks.Count -eq 0 }

            # A subsequent normal call must still work — the module isn't left broken.
            $recovered = $false
            try {
                Start-ProgressScope -ScriptBlock {
                    Write-ProgressBar -Activity 'recovery-check' -Current 1 -Total 1
                    Write-ProgressBar -Activity 'recovery-check' -Completed
                } | Out-Null
                $recovered = $true
            }
            catch { $recovered = $false }

            return ($contextNull -and $tasksEmpty -and $recovered)
        }

        Test-Case "Write-StatusMessage still uses Write-SpectreHost outside a scope" {
            if (-not $script:IsSpectreRun) { return 'SKIP' }
            $script:UICapture.Clear()
            Write-StatusMessage 'outside-scope' -Type Info
            $line = $script:UICapture -join "`n"
            return ($line -match 'outside-scope')
        }

        Test-Case "backend natif : Write-StatusMessage produit une sortie prefixee" {
            if ($script:IsSpectreRun) { return 'SKIP' }
            $out = (Write-StatusMessage 'native-success' -Type Success 6>&1 | Out-String)
            return ($out -match 'OK:') -and ($out -match 'native-success')
        }

        Test-Case "backend natif : chaque type de message est rendu" {
            if ($script:IsSpectreRun) { return 'SKIP' }
            foreach ($t in @('Info', 'Success', 'Warning', 'Error', 'Skipped', 'Debug')) {
                $out = (Write-StatusMessage "type-$t" -Type $t 6>&1 | Out-String)
                if ($out -notmatch "type-$t") { return "type $t sans sortie" }
            }
            return $true
        }

        Test-Case "backend natif : Write-Header trace une regle avec le titre" {
            if ($script:IsSpectreRun) { return 'SKIP' }
            $out = (Write-Header 'Titre natif' 6>&1 | Out-String)
            # Le filet est U+2500 en UTF-8, '-' sinon : le test suit la meme regle
            # que Get-RuleCharNative plutot que de supposer un encodage.
            $rule = if (-not [Console]::IsOutputRedirected -and [Console]::OutputEncoding.CodePage -eq 65001) { [char]0x2500 } else { '-' }
            return ($out -match 'Titre natif') -and ($out.Contains([string]$rule))
        }

        Test-Case "backend natif : Start-ProgressScope execute le scriptblock" {
            if ($script:IsSpectreRun) { return 'SKIP' }
            $marker = [System.Collections.Generic.List[object]]::new()
            Start-ProgressScope -ScriptBlock {
                Write-ProgressBar -Activity 'natif' -Current 1 -Total 2
                $marker.Add('execute')
                Write-ProgressBar -Activity 'natif' -Completed
            }
            return ($marker.Count -eq 1 -and $marker[0] -eq 'execute')
        }

        Test-Case "Write-Summary does not throw" {
            try { Write-Summary; return $true }
            catch { return $false }
        }
    }

    Write-TestHeader "PS7-Core.UI — Read-FolderSelection"

    # Scratch tree: root/, root/subA/nested, root/subB, root/excluded-a
    $rfsRoot = Join-Path $tempDir 'rfs-root'
    New-Item -ItemType Directory -Path $rfsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $rfsRoot 'subA') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $rfsRoot 'subA/nested') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $rfsRoot 'subB') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $rfsRoot 'excluded-a') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $rfsRoot 'excluded-a/child') -Force | Out-Null

    Test-Case "non-interactive returns direct subfolders only" {
        $result = @(Read-FolderSelection -Path $rfsRoot -ExcludeName 'excluded-a', 'excluded-b')
        return (
            $result.Count -eq 2 -and
            -not ($result -contains $rfsRoot) -and
            $result -contains (Join-Path $rfsRoot 'subA') -and
            $result -contains (Join-Path $rfsRoot 'subB')
        )
    }

    Test-Case "nested subfolders are not returned" {
        $result = @(Read-FolderSelection -Path $rfsRoot -ExcludeName 'excluded-a', 'excluded-b')
        return -not ($result -contains (Join-Path $rfsRoot 'subA/nested'))
    }

    Test-Case "excluded subfolder names are left out" {
        $result = @(Read-FolderSelection -Path $rfsRoot -ExcludeName 'excluded-a', 'excluded-b')
        return -not ($result -contains (Join-Path $rfsRoot 'excluded-a'))
    }

    Test-Case "root name does not affect direct-subfolder selection" {
        $excludedRoot = Join-Path $rfsRoot 'excluded-a'
        $result = @(Read-FolderSelection -Path $excludedRoot -ExcludeName 'excluded-a', 'excluded-b')
        return (
            $result.Count -eq 1 -and
            $result -contains (Join-Path $excludedRoot 'child')
        )
    }

    Test-Case "non-existent path throws" {
        try {
            Read-FolderSelection -Path (Join-Path $tempDir 'does-not-exist') | Out-Null
            return $false
        }
        catch { return $true }
    }

    Test-Case "-Interactive with redirected input keeps everything" {
        # [Console]::IsInputRedirected is true in this test host, so Read-Selection's
        # redirected-input guard fires and every candidate is kept unfiltered.
        $result = @(Read-FolderSelection -Path $rfsRoot -ExcludeName 'excluded-a', 'excluded-b' -Interactive)
        return ($result.Count -eq 2)
    }
}

#endregion


#region PS7-Core.Crypto tests
################################################################################

if (-not $OnlyRuntime -and -not $OnlyUI) {
    Write-TestHeader "PS7-Core.Crypto - hachage de fichiers et de chaines"

    # Vecteurs de reference publics : le hachage est un contrat exact, on compare
    # a des constantes connues plutot qu'a une seconde execution du meme code.
    $abcSha256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    $abcMd5 = '900150983cd24fb0d6963f7d28e17f72'

    $cryptoDir = Join-Path $tempDir 'crypto'
    New-Item -ItemType Directory -Path $cryptoDir -Force | Out-Null

    # -Encoding Byte n'existe plus en PS7 : on ecrit les octets directement pour
    # ne pas laisser Set-Content ajouter une fin de ligne au vecteur.
    $abcFile = Join-Path $cryptoDir 'abc.txt'
    [System.IO.File]::WriteAllBytes($abcFile, [System.Text.Encoding]::ASCII.GetBytes('abc'))

    # Nom canonique d'un doublon telecharge, et motif joker pour -Path : c'est le
    # cas qui distingue Test-Path -Path de -LiteralPath.
    $bracketFile = Join-Path $cryptoDir 'copie[1].txt'
    [System.IO.File]::WriteAllBytes($bracketFile, [System.Text.Encoding]::ASCII.GetBytes('abc'))

    Test-Case "Get-StringHash SHA256 matches the reference vector" {
        return ((Get-StringHash -String 'abc') -eq $abcSha256)
    }

    Test-Case "Get-StringHash honours -Algorithm and -UpperCase" {
        return (
            (Get-StringHash -String 'abc' -Algorithm MD5) -eq $abcMd5 -and
            (Get-StringHash -String 'abc' -UpperCase) -eq $abcSha256.ToUpper()
        )
    }

    Test-Case "Get-StringHash is encoding-sensitive" {
        # Un meme texte hache differemment en UTF8 et en Unicode : verifie que le
        # parametre est reellement pris en compte, pas ignore silencieusement.
        return ((Get-StringHash -String 'abc' -Encoding Unicode) -ne $abcSha256)
    }

    Test-Case "Get-FileHashExtended matches the reference vector" {
        return ((Get-FileHashExtended -Path $abcFile) -eq $abcSha256)
    }

    Test-Case "Get-FileHashExtended hashes a name containing brackets" {
        return ((Get-FileHashExtended -Path $bracketFile) -eq $abcSha256)
    }

    Test-Case "Get-FileHashExtended errors on a missing file" {
        $result = Get-FileHashExtended -Path (Join-Path $cryptoDir 'absent.txt') -ErrorAction SilentlyContinue
        return ($null -eq $result)
    }

    Test-Case "Get-FileHashExtended rejects a directory" {
        $result = Get-FileHashExtended -Path $cryptoDir -ErrorAction SilentlyContinue
        return ($null -eq $result)
    }

    Test-Case "Test-FileIntegrity accepts the expected hash, any case" {
        return (
            (Test-FileIntegrity -Path $abcFile -ExpectedHash $abcSha256) -and
            (Test-FileIntegrity -Path $abcFile -ExpectedHash $abcSha256.ToUpper())
        )
    }

    Test-Case "Test-FileIntegrity rejects a mismatched hash" {
        $wrong = '0' * 64
        return (-not (Test-FileIntegrity -Path $abcFile -ExpectedHash $wrong -WarningAction SilentlyContinue))
    }

    Test-Case "Test-FileIntegrity compares with the requested algorithm" {
        return (Test-FileIntegrity -Path $abcFile -ExpectedHash $abcMd5 -Algorithm MD5)
    }

    Test-Case "Test-FileIntegrity returns false on a missing file" {
        $missing = Join-Path $cryptoDir 'absent.txt'
        return (-not (Test-FileIntegrity -Path $missing -ExpectedHash $abcSha256 -ErrorAction SilentlyContinue))
    }
}

#endregion


#region Final report
################################################################################

Write-Host ""
Write-Host ("=" * 72) -ForegroundColor Cyan
Write-Host "  Results" -ForegroundColor Cyan
Write-Host ("=" * 72) -ForegroundColor Cyan
Write-Host ("  PASS : {0}" -f $script:TestStats.Pass) -ForegroundColor Green
Write-Host ("  FAIL : {0}" -f $script:TestStats.Fail) -ForegroundColor Red
Write-Host ("  SKIP : {0}" -f $script:TestStats.Skip) -ForegroundColor Yellow

if ($script:TestFailures.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($f in $script:TestFailures) {
        Write-Host "    - $f" -ForegroundColor Red
    }
}

# Cleanup
try { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}

Write-Host ""
exit ([int]($script:TestStats.Fail -gt 0))

#endregion
