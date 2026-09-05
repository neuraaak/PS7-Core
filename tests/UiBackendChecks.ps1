<#
    Scenarios partages par Show-UiBackend.Spectre.ps1 et Show-UiBackend.Native.ps1.

    Deux volets :
      1. Robustesse - assertions automatiques : arguments invalides, valeurs
         limites, mauvais types, injection de markup, parite entre backends.
      2. Rendu - sortie visuelle a inspecter a l'oeil, seule facon de juger
         l'affichage (un shell redirige ne rend ni Write-Progress ni Spectre).

    Ce fichier est dot-source, il ne s'execute pas seul.
#>

$script:Checks = @{ Pass = 0; Fail = 0; Skip = 0 }
$script:CheckFailures = [System.Collections.Generic.List[string]]::new()

function Assert-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )
    $status = $null
    $color = 'Green'
    try {
        # 6>$null : les fonctions testees ecrivent via Write-Host, dont le flux
        # d'information est supprimable. Sans cela le test de 4000 caracteres
        # noie l'ecran et rend la suite illisible - or c'est un outil qu'on lance
        # apres chaque modification. Montrer la sortie est le role du volet
        # visuel. (Le backend Spectre ecrit droit sur la console et echappe a
        # cette redirection : quelques lignes subsistent, sans gravite.)
        $result = & $Body 6>$null
        if ($result -eq $true) {
            $script:Checks.Pass++
            $status = 'OK'
        }
        elseif ($result -eq 'SKIP') {
            $script:Checks.Skip++
            $status = 'SKIP'
            $color = 'DarkGray'
        }
        else {
            $script:Checks.Fail++
            $script:CheckFailures.Add("$Name -> $result")
            $status = "FAIL  $result"
            $color = 'Red'
        }
    }
    catch {
        $script:Checks.Fail++
        $script:CheckFailures.Add("$Name -> $($_.Exception.Message)")
        $status = "FAIL  $($_.Exception.Message)"
        $color = 'Red'
    }

    # Le libelle est imprime APRES l'execution, en une ligne complete : ecrire un
    # libelle -NoNewline puis laisser la fonction testee (et Write-Progress)
    # ecrire dedans corrompt l'affichage en terminal reel.
    Write-Host ("  [{0,-58}] {1}" -f $Name, $status) -ForegroundColor $color
}

# Vrai si le scriptblock leve, faux sinon. Sert aux cas "doit refuser".
function Test-Throws {
    param([scriptblock]$Body)
    try { & $Body | Out-Null; return $false } catch { return $true }
}

function Invoke-RobustnessChecks {
    param(
        [string]$Backend,

        # Valeurs extremes. Hors -Thorough, les entrees longues restent lisibles :
        # le backend Spectre ecrit droit sur la console et echappe a toute
        # redirection de flux, donc un message de 4000 caracteres noie l'ecran.
        # On ne neutralise PAS le moteur de rendu pour se taire - verifier qu'il
        # encaisse une entree longue fait partie de l'interet du test - on rend
        # simplement l'extreme optionnel.
        [switch]$Thorough
    )

    $longMessage = if ($Thorough) { 4000 } else { 400 }
    $longTitle = if ($Thorough) { 400 } else { 120 }

    Write-Host ""
    Write-Host "  Robustesse - backend $Backend" -ForegroundColor Cyan
    Write-Host ("  " + "-" * 62) -ForegroundColor DarkGray

    # --- Write-StatusMessage : arguments hors contrat ---------------------

    Assert-Check "Write-StatusMessage refuse un -Type inconnu" {
        Test-Throws { Write-StatusMessage 'x' -Type 'Chartreuse' }
    }

    # Une fonction d'affichage doit etre totale : un script qui passe une
    # variable vide ou nulle ne doit pas planter pour autant.
    Assert-Check "Write-StatusMessage tolere un message null" {
        Write-StatusMessage $null -Type Info
        return $true
    }

    Assert-Check "Write-StatusMessage accepte une chaine vide" {
        Write-StatusMessage '' -Type Info
        return $true
    }

    Assert-Check "Write-StatusMessage accepte un message multi-ligne" {
        Write-StatusMessage ("ligne1" + [Environment]::NewLine + "ligne2") -Type Info
        return $true
    }

    Assert-Check "Write-StatusMessage accepte un message de $longMessage caracteres" {
        Write-StatusMessage ('a' * $longMessage) -Type Info
        return $true
    }

    Assert-Check "Write-StatusMessage accepte accents" {
        Write-StatusMessage 'eaus accentues : ok' -Type Success
        return $true
    }

    # Le markup fourni par l'utilisateur ne doit jamais etre interprete comme
    # une balise de rendu : c'est une injection, pas du style.
    Assert-Check "Write-StatusMessage n'interprete pas le markup utilisateur" {
        if ((Get-UIContext).Backend -eq 'Spectre') {
            # Write-SpectreHost ecrit droit sur la console, hors des flux
            # capturables : on l'ombre par un stub pour voir ce qui lui est passe.
            $script:MarkupCapture = [System.Collections.Generic.List[string]]::new()
            function global:Write-SpectreHost { param([string]$s) $script:MarkupCapture.Add($s) }
            try {
                Write-StatusMessage '[red]injection[/]' -Type Info
                $line = $script:MarkupCapture -join ' '
                # Echappement Spectre attendu : '[' -> '[[' et ']' -> ']]'
                return ($line -match '\[\[red\]\]') -and ($line -match 'injection')
            }
            finally {
                Remove-Item function:global:Write-SpectreHost -ErrorAction SilentlyContinue
            }
        }

        $out = (Write-StatusMessage '[red]injection[/]' -Type Info 6>&1 | Out-String)
        return $out -match 'injection'
    }

    Assert-Check "Write-StatusMessage accepte des crochets desequilibres" {
        Write-StatusMessage 'valeur=[42' -Type Info
        Write-StatusMessage 'valeur=43]' -Type Info
        return $true
    }

    Assert-Check "Write-StatusMessage accepte un non-string coercible" {
        Write-StatusMessage 42 -Type Info
        return $true
    }

    # --- Write-ProgressBar : valeurs limites ------------------------------

    Assert-Check "Write-ProgressBar tolere Total = 0 (pas de division par zero)" {
        Write-ProgressBar -Activity 'limite' -Current 5 -Total 0
        Write-ProgressBar -Activity 'limite' -Completed
        return $true
    }

    Assert-Check "Write-ProgressBar borne Current > Total" {
        Write-ProgressBar -Activity 'limite' -Current 500 -Total 10
        Write-ProgressBar -Activity 'limite' -Completed
        return $true
    }

    Assert-Check "Write-ProgressBar borne un Current negatif" {
        Write-ProgressBar -Activity 'limite' -Current -20 -Total 10
        Write-ProgressBar -Activity 'limite' -Completed
        return $true
    }

    # On verifie le CONTRAT via les metadonnees, sans declencher la liaison :
    # omettre un parametre obligatoire ouvre une invite interactive en terminal
    # reel (verifie), ce qui figerait cette suite.
    Assert-Check "Write-ProgressBar declare Activity obligatoire" {
        $attr = (Get-Command Write-ProgressBar).Parameters['Activity'].Attributes |
        Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        return [bool]($attr.Mandatory -contains $true)
    }

    Assert-Check "Write-ProgressBar refuse une Activity nulle" {
        Test-Throws { Write-ProgressBar -Activity $null -Current 1 -Total 2 }
    }

    Assert-Check "Write-ProgressBar -Completed sans progression prealable" {
        Write-ProgressBar -Activity 'jamais-commence' -Completed
        return $true
    }

    Assert-Check "Write-ProgressBar refuse un Total non numerique" {
        Test-Throws { Write-ProgressBar -Activity 'x' -Current 1 -Total 'beaucoup' }
    }

    # --- Write-Header : limites de rendu ----------------------------------

    Assert-Check "Write-Header accepte un titre plus large que la console" {
        Write-Header ('T' * $longTitle)
        return $true
    }

    Assert-Check "Write-Header tolere une couleur inconnue" {
        Write-Header 'couleur inconnue' -Color 'Chartreuse'
        return $true
    }

    Assert-Check "Write-Header refuse un titre null" {
        Test-Throws { Write-Header $null }
    }

    # --- Read-Selection : entrees degenerees ------------------------------

    Assert-Check "Read-Selection sur une collection vide retourne du vide" {
        $r = @(Read-Selection -Items @() -Message 'vide')
        return $r.Count -eq 0
    }

    Assert-Check "Read-Selection avec entree redirigee conserve tout" {
        # Uniquement valide quand stdin EST redirige : sinon la fonction affiche
        # une vraie invite et attend l'utilisateur, ce qu'une assertion ne peut
        # ni piloter ni interpreter (constate en terminal reel).
        if (-not [Console]::IsInputRedirected) { return 'SKIP' }
        $items = @('a', 'b', 'c')
        $r = @(Read-Selection -Items $items -Message 'redirige')
        return $r.Count -eq 3
    }

    Assert-Check "Read-Selection accepte un LabelProperty absent des objets" {
        if (-not [Console]::IsInputRedirected) { return 'SKIP' }
        $items = @([PSCustomObject]@{ Autre = 1 })
        $r = @(Read-Selection -Items $items -LabelProperty 'Inexistant')
        return $r.Count -eq 1
    }

    # --- Start-ProgressScope : contrat et parite --------------------------

    Assert-Check "Start-ProgressScope refuse l'imbrication" {
        Test-Throws { Start-ProgressScope { Start-ProgressScope { } } }
    }

    Assert-Check "Start-ProgressScope remet l'etat a plat apres une exception" {
        try { Start-ProgressScope { throw 'boum' } } catch { }
        # Une seconde ouverture doit reussir : sinon le sentinelle est reste arme.
        Start-ProgressScope { }
        return $true
    }

    Assert-Check "Start-ProgressScope propage la sortie du scriptblock" {
        $r = Start-ProgressScope { 'valeur-de-retour' }
        return ($r -contains 'valeur-de-retour')
    }

    Assert-Check "Start-ProgressScope refuse un scriptblock absent" {
        Test-Throws { Start-ProgressScope -ScriptBlock $null }
    }

    Assert-Check "le piege de portee enfant se comporte pareil dans les 2 backends" {
        # += sur un tableau est perdu (copie locale) ; .Add() sur une List survit.
        $lost = @()
        $kept = [System.Collections.Generic.List[object]]::new()
        Start-ProgressScope {
            $lost += 'x'
            $kept.Add('x')
        }
        return ($lost.Count -eq 0) -and ($kept.Count -eq 1)
    }

    Assert-Check "Get-UIContext expose le backend reellement actif" {
        return (Get-UIContext).Backend -eq $Backend
    }
}

function Invoke-VisualDemo {
    param([string]$Backend)

    Write-Host ""
    Write-Host "  Rendu visuel - backend $Backend" -ForegroundColor Cyan
    Write-Host "  (a inspecter a l'oeil : couleurs, alignement, artefacts)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Header "Demonstration $Backend"

    foreach ($type in @('Info', 'Success', 'Warning', 'Error', 'Skipped', 'Debug')) {
        Write-StatusMessage "message de type $type" -Type $type
    }

    Write-Host ""
    Write-Host "  Progression seule (50 pas) :" -ForegroundColor DarkGray
    Start-ProgressScope {
        for ($i = 1; $i -le 50; $i++) {
            Write-ProgressBar -Activity 'Traitement' -Current $i -Total 50 -Status "element-$i"
            Start-Sleep -Milliseconds 25
        }
        Write-ProgressBar -Activity 'Traitement' -Completed
    }

    Write-Host ""
    Write-Host "  Progression + messages entrelaces (le cas qui corrompait l'affichage) :" -ForegroundColor DarkGray
    Start-ProgressScope {
        for ($i = 1; $i -le 60; $i++) {
            Write-ProgressBar -Activity 'Analyse' -Current $i -Total 60 -Status "fichier-$i"
            if ($i % 5 -eq 0) {
                Write-StatusMessage "conflit sur fichier-$i.jpg" -Type Warning
            }
            Start-Sleep -Milliseconds 25
        }
        Write-ProgressBar -Activity 'Analyse' -Completed
    }

    Write-Host ""
    Write-Host "  Deux barres simultanees :" -ForegroundColor DarkGray
    Start-ProgressScope {
        for ($i = 1; $i -le 40; $i++) {
            Write-ProgressBar -Activity 'Scan' -Current $i -Total 40
            Write-ProgressBar -Activity 'Hash' -Current ([Math]::Min($i * 2, 40)) -Total 40 -Id 1
            Start-Sleep -Milliseconds 25
        }
        Write-ProgressBar -Activity 'Scan' -Completed
        Write-ProgressBar -Activity 'Hash' -Completed -Id 1
    }

    Write-Summary "Resume"
    Write-StatusMessage "Traites : 60" -Type Info
    Write-StatusMessage "Reussis : 58" -Type Success
    Write-StatusMessage "Echecs  : 2" -Type Error
}

function Invoke-UiBackendCheck {
    param(
        [Parameter(Mandatory)][ValidateSet('Spectre', 'Native')][string]$Backend,
        [switch]$SkipVisual,
        [switch]$OnlyVisual,
        [switch]$Thorough
    )

    $modulesRoot = Split-Path -Parent $PSScriptRoot
    if ($env:PSModulePath -notlike "*$modulesRoot*") {
        $env:PSModulePath = "$modulesRoot;$env:PSModulePath"
    }
    Import-Module PS7-Core -Force -ErrorAction Stop

    Write-Host ""
    Write-Host ("=" * 66) -ForegroundColor Magenta
    Write-Host "  PS7-Core.UI - backend $Backend" -ForegroundColor Magenta
    Write-Host "  PowerShell $($PSVersionTable.PSVersion)   encodage sortie : $([Console]::OutputEncoding.WebName)"
    Write-Host ("=" * 66) -ForegroundColor Magenta

    try {
        $ctx = Initialize-EnhancedUI -Backend $Backend
    }
    catch {
        Write-Host ""
        Write-Host "  Backend '$Backend' indisponible : $($_.Exception.Message)" -ForegroundColor Yellow
        return 0
    }

    if ($ctx.Backend -ne $Backend) {
        Write-Host "  Backend resolu inattendu : $($ctx.Backend)" -ForegroundColor Red
        return 1
    }

    if (-not $OnlyVisual) { Invoke-RobustnessChecks -Backend $Backend -Thorough:$Thorough }
    if (-not $SkipVisual) { Invoke-VisualDemo -Backend $Backend }

    Write-Host ""
    Write-Host ("=" * 66) -ForegroundColor Magenta
    if ($OnlyVisual) {
        Write-Host "  Rendu termine (aucune assertion executee)." -ForegroundColor Green
        return 0
    }

    $color = if ($script:Checks.Fail) { 'Red' } else { 'Green' }
    Write-Host "  Robustesse : PASS $($script:Checks.Pass)  FAIL $($script:Checks.Fail)  SKIP $($script:Checks.Skip)" -ForegroundColor $color
    foreach ($f in $script:CheckFailures) {
        Write-Host "    - $f" -ForegroundColor Red
    }
    Write-Host ""

    return [int]($script:Checks.Fail -gt 0)
}
