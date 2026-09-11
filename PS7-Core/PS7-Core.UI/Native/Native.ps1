<#
    Backend natif de PS7-Core.UI — PowerShell 7 pur, sans dépendance externe.

    Utilisé quand PwshSpectreConsole est absent (poste où Spectre est bloqué),
    ou quand Initialize-EnhancedUI -Backend Native le force.

    Ce fichier est dot-sourcé par PS7-Core.UI.psm1 au chargement du module, donc
    ses fonctions vivent dans la portée du module et voient les variables
    $script:*. Elles sont internes : seules les fonctions publiques du .psm1
    sont exportées.

    Objectif : un rendu ACCEPTABLE, pas identique à Spectre. Viser l'équivalence
    visuelle ramènerait aux impasses déjà rencontrées (barre inline maison dont
    les lignes de statut se collaient à la progression).
#>

# Largeur de console utilisable, avec repli quand il n'y a pas de vrai hôte
# (sortie redirigée, tâche planifiée) : RawUI.WindowSize y lève ou renvoie 0.
function Get-ConsoleWidthNative {
    try {
        $width = $Host.UI.RawUI.WindowSize.Width
        if ($width -gt 20) { return [Math]::Min($width - 1, 120) }
    }
    catch {
        Write-Verbose "Console width unavailable, using default: $_"
    }
    return 78
}

function Write-StatusMessageNative {
    param(
        [string]$Message,
        [string]$Type
    )

    # Mêmes préfixes et mêmes couleurs que le backend Spectre, afin qu'un script
    # produise une sortie reconnaissable quel que soit le backend actif.
    switch ($Type) {
        'Info' { Write-Host $Message -ForegroundColor Cyan }
        'Success' { Write-Host "OK: " -ForegroundColor Green -NoNewline; Write-Host $Message }
        'Warning' { Write-Host "WARN: " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
        'Error' { Write-Host "ERROR: " -ForegroundColor Red -NoNewline; Write-Host $Message }
        'Skipped' { Write-Host "SKIP: " -ForegroundColor DarkGray -NoNewline; Write-Host $Message }
        'Debug' { Write-Host "DEBUG: " -ForegroundColor DarkGray -NoNewline; Write-Host $Message }
        default { Write-Host $Message }
    }
}

# Caractere de filet. U+2500 n'est lisible que si la sortie est reellement en
# UTF-8 : sur un hote a encodage hérité (PS7 dezippé, console legacy, sortie
# redirigee) il ressort en mojibake. Le backend natif vise justement ces hotes,
# et le risque est asymetrique - l'ASCII passe toujours - donc on ne prend le
# trait fin que lorsqu'on a la preuve que l'encodage le supporte.
function Get-RuleCharNative {
    try {
        # Sortie redirigee : [Console]::OutputEncoding ne dit rien du decodeur en
        # aval (fichier, pipe, capture CI), et le trait fin y ressort en mojibake.
        # L'ASCII garde les journaux lisibles.
        if ([Console]::IsOutputRedirected) { return '-' }

        if ([Console]::OutputEncoding.CodePage -eq 65001) { return [string][char]0x2500 }
    }
    catch {
        Write-Verbose "Output encoding unavailable: $_"
    }
    return '-'
}

function Write-HeaderNative {
    param(
        [string]$Title,
        [string]$Color = 'Cyan'
    )

    # Équivalent d'une Spectre Rule : un titre encadré de traits horizontaux.
    # Volontairement plus pauvre — c'est le prix assumé du mode dégradé.
    $consoleColor = try { [System.ConsoleColor]$Color } catch { [System.ConsoleColor]::Cyan }

    $width = Get-ConsoleWidthNative
    $label = " $Title "
    $lead = 2
    $trail = [Math]::Max(0, $width - $lead - $label.Length)
    $rule = Get-RuleCharNative

    Write-Host ($rule * $lead) -ForegroundColor DarkGray -NoNewline
    Write-Host $label -ForegroundColor $consoleColor -NoNewline
    Write-Host ($rule * $trail) -ForegroundColor DarkGray
}

function Write-ProgressBarNative {
    param(
        [string]$Activity,
        [int]$Current,
        [int]$Total,
        [string]$Status,
        [int]$Id,
        [int]$ParentId,
        [switch]$Completed
    )

    # Write-Progress natif, vue Minimal : validé sous forte charge d'impression
    # (repro manuel du 2026-09-04, -PrintEvery 1 sur 5000 items). Il occupe une
    # région de terminal dédiée et ne pollue donc jamais le flux texte.
    if ($Completed) {
        Write-Progress -Activity $Activity -Id $Id -Completed
        return
    }

    $percentComplete = if ($Total -gt 0) { ($Current / $Total) * 100 } else { 0 }
    $percentComplete = [Math]::Min(100, [Math]::Max(0, $percentComplete))

    $progressParams = @{
        Activity        = $Activity
        Status          = if ($Status) { $Status } else { "$Current of $Total" }
        PercentComplete = $percentComplete
        Id              = $Id
    }

    if ($ParentId -ge 0) {
        $progressParams['ParentId'] = $ParentId
    }

    Write-Progress @progressParams
}

function Start-ProgressScopeNative {
    param(
        [scriptblock]$ScriptBlock
    )

    # Passe-plat : il n'y a pas de région live à ouvrir en natif, Write-ProgressBar
    # utilise directement Write-Progress. Le scope reste néanmoins un VRAI scope —
    # même invocation via '&' que le backend Spectre — pour que le piège de portée
    # enfant (une variable réaffectée dedans est perdue à la sortie ; utiliser
    # List[object] + .Add()) se comporte à l'identique dans les deux backends.
    # Un script validé sur un backend se comporte donc pareil sur l'autre.
    try {
        & $ScriptBlock $null
    }
    finally {
        # Rien à démonter côté rendu, mais on aligne le nettoyage sur Spectre.
        $script:ProgressTasks = @{}
    }
}

function Read-SelectionNative {
    param(
        [object[]]$Items,
        [PSCustomObject[]]$Choices,
        [string]$Message
    )

    # Invite texte numérotée. Sert à la fois de backend natif et de repli au
    # backend Spectre quand son prompt plante à l'exécution.
    Write-Host ""
    Write-StatusMessage $Message -Type Info

    for ($i = 0; $i -lt $Choices.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $Choices[$i].Label)
    }

    Write-Host ""
    $answer = Read-Host "Entries to keep (e.g. 1,3,5 - '*' for all - empty for none)"
    $answer = $answer.Trim()

    if ([string]::IsNullOrEmpty($answer)) {
        return @()
    }

    if ($answer -eq '*') {
        return $Items
    }

    $picked = @()

    foreach ($token in $answer.Split(',')) {
        $token = $token.Trim()
        $index = 0

        if ([int]::TryParse($token, [ref]$index) -and $index -ge 1 -and $index -le $Choices.Count) {
            $picked += $Choices[$index - 1].Value
        }
        else {
            Write-StatusMessage "Ignored invalid entry: $token" -Type Warning
        }
    }

    return $picked
}

function Initialize-ConsoleHostNative {
    # Le conhost hérité (un .cmd double-cliqué depuis l'Explorateur) n'active pas
    # le traitement VT100/ANSI par défaut, ce qui fait échouer les prompts
    # interactifs de Spectre. Sans dépendance : c'est du P/Invoke Win32, donc ce
    # setup appartient au backend natif et sert aux deux.
    if ($env:OS -eq 'Windows_NT') {
        try {
            $signature = @(
                '[DllImport("kernel32.dll")] public static extern bool GetStdHandle(int handle, out System.IntPtr result);'
                '[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr handle, out int mode);'
                '[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr handle, int mode);'
            ) -join [Environment]::NewLine

            $type = Add-Type -MemberDefinition $signature -Name 'ConsoleVT' -Namespace 'PS7CoreUI' -PassThru -ErrorAction Stop

            $STD_OUTPUT_HANDLE = -11
            $ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x4

            $handle = [System.IntPtr]::Zero
            if ($type::GetStdHandle($STD_OUTPUT_HANDLE, [ref]$handle)) {
                $mode = 0
                if ($type::GetConsoleMode($handle, [ref]$mode)) {
                    $null = $type::SetConsoleMode($handle, $mode -bor $ENABLE_VIRTUAL_TERMINAL_PROCESSING)
                }
            }
        }
        catch {
            Write-Verbose "Failed to enable VT100 processing on the console: $_"
        }
    }

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
    }
    catch {
        Write-Verbose "Failed to set UTF-8 encoding: $_"
    }
}

function Read-ConfirmationNative {
    param(
        [string]$Message,
        [bool]$DefaultValue
    )

    # Sert aussi de repli au backend Spectre quand son prompt plante.
    $hint = if ($DefaultValue) { '[Y/n]' } else { '[y/N]' }

    while ($true) {
        Write-Host ""
        $answer = (Read-Host "$Message $hint").Trim()

        # Entrée vide = on accepte le défaut proposé par le libellé.
        if ([string]::IsNullOrEmpty($answer)) {
            return $DefaultValue
        }

        switch -Regex ($answer) {
            '^(y|yes|o|oui)$' { return $true }
            '^(n|no|non)$' { return $false }
            default {
                Write-StatusMessage "Answer 'y' or 'n'." -Type Warning
            }
        }
    }
}

function Read-TextInputNative {
    param(
        [string]$Message,
        [string]$Default,
        [bool]$HasDefault,
        [bool]$AllowEmpty,
        [scriptblock]$Validate
    )

    $hint = if ($HasDefault -and -not [string]::IsNullOrEmpty($Default)) { " [$Default]" } else { '' }

    while ($true) {
        Write-Host ""
        $answer = (Read-Host "$Message$hint").Trim()

        if ([string]::IsNullOrEmpty($answer) -and $HasDefault) {
            $answer = $Default
        }

        $rejection = Get-TextInputRejectionNative -Value $answer -AllowEmpty $AllowEmpty -Validate $Validate

        if ($null -eq $rejection) {
            return $answer
        }

        Write-StatusMessage $rejection -Type Warning
    }
}

function Get-TextInputRejectionNative {
    <#
        Retourne $null quand la valeur est acceptable, sinon le motif du refus.
        Partagé par les deux backends ET par la garde non-interactive : c'est le
        seul endroit qui décide ce qu'est une saisie valide, pour qu'une valeur
        refusée à l'invite ne puisse pas être acceptée comme défaut.
    #>
    param(
        [string]$Value,
        [bool]$AllowEmpty,
        [scriptblock]$Validate
    )

    if ([string]::IsNullOrEmpty($Value) -and -not $AllowEmpty) {
        return 'A value is required.'
    }

    if ($null -eq $Validate) {
        return $null
    }

    # $_ dans le scriptblock de validation : c'est la convention PowerShell
    # (ValidateScript), et l'appelant l'attend plutôt qu'un paramètre nommé.
    $accepted = ForEach-Object -InputObject $Value -Process $Validate

    if ($accepted) {
        return $null
    }

    return "Value '$Value' is not valid."
}

function Start-SpinnerNative {
    param(
        [string]$Message,
        [scriptblock]$ScriptBlock
    )

    # Pas d'animation ici : la faire tourner demanderait un runspace concurrent
    # pour un gain purement cosmétique. Le backend natif annonce puis exécute,
    # comme il le fait déjà pour la barre de progression.
    Write-StatusMessage "$Message..." -Type Info
    return & $ScriptBlock
}
