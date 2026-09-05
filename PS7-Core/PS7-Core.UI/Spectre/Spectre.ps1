<#
    Backend Spectre.Console de PS7-Core.UI, adossé à PwshSpectreConsole.

    Dot-sourcé par PS7-Core.UI.psm1 au chargement du module, TOUJOURS — y compris
    quand PwshSpectreConsole est absent. Définir ces fonctions ne coûte rien :
    seuls leurs corps ont besoin de la lib, à l'appel. C'est ce qui permet de
    forcer l'un ou l'autre backend depuis une machine où Spectre est installé,
    et donc de tester le chemin natif sans machine dédiée.
#>

function Test-SpectreAvailable {
    if (Get-Command Write-SpectreHost -ErrorAction SilentlyContinue) {
        return $true
    }

    if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
        Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
    }

    return [bool](Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)
}

function Write-StatusMessageSpectre {
    param(
        [string]$Message,
        [string]$Type
    )

    # Le markup est requis pour la couleur : Write-SpectreHost sans [tags] rend
    # du texte brut. On échappe les [ ] du contenu utilisateur pour ne pas casser
    # le parseur de markup.
    $safe = $Message -replace '\[', '[[' -replace '\]', ']]'
    $markup = switch ($Type) {
        'Info' { "[cyan]$safe[/]" }
        'Success' { "[green]OK:[/] $safe" }
        'Warning' { "[yellow]WARN:[/] $safe" }
        'Error' { "[red]ERROR:[/] $safe" }
        'Skipped' { "[grey]SKIP:[/] $safe" }
        'Debug' { "[grey]DEBUG:[/] $safe" }
        default { $safe }
    }

    if ($null -ne $script:CurrentProgressContext) {
        # Write-SpectreHost glitche depuis l'intérieur d'une région live Spectre
        # (vérifié manuellement) ; AnsiConsole.MarkupLine non.
        [Spectre.Console.AnsiConsole]::MarkupLine($markup)
    }
    else {
        Write-SpectreHost $markup
    }
}

function Write-HeaderSpectre {
    param(
        [string]$Title,
        [string]$Color = 'Cyan'
    )

    try {
        Write-SpectreRule -Title $Title -Color $Color
    }
    catch {
        Write-SpectreHost $Title
    }
}

function Write-ProgressBarSpectre {
    param(
        [string]$Activity,
        [int]$Current,
        [int]$Total,
        [string]$Status,
        [switch]$Completed
    )

    # Appelée uniquement depuis l'intérieur d'un Start-ProgressScope Spectre :
    # une tâche du ProgressContext live par Activity distincte, pour que barre et
    # flot de messages coexistent sans corrompre la console.
    if (-not $script:ProgressTasks.ContainsKey($Activity)) {
        $script:ProgressTasks[$Activity] = $script:CurrentProgressContext.AddTask($Activity)
    }
    $task = $script:ProgressTasks[$Activity]

    if ($Completed) {
        $task.Value = 100
        $task.StopTask()
        $script:ProgressTasks.Remove($Activity)
        return
    }

    $percentComplete = if ($Total -gt 0) { ($Current / $Total) * 100 } else { 0 }
    $percentComplete = [Math]::Min(100, [Math]::Max(0, $percentComplete))

    $task.Description = if ($Status) { "$Activity - $Status" } else { $Activity }
    $task.Value = $percentComplete
}

function Start-ProgressScopeSpectre {
    param(
        [scriptblock]$ScriptBlock
    )

    # Volontairement PAS de .GetNewClosure() : Spectre invoque ce scriptblock
    # depuis l'intérieur de son propre callback (Progress.Start()), et
    # GetNewClosure() le détacherait sur une copie privée des variables $script:
    # du module — les écritures sur $script:CurrentProgressContext deviendraient
    # invisibles à Write-ProgressBar / Write-StatusMessage, qui lisent la vraie
    # portée du module (vérifié empiriquement). On range donc le scriptblock
    # utilisateur dans une variable de module plutôt que dans une capture.
    $script:ActiveScopeScriptBlock = $ScriptBlock

    $wrapped = {
        param([Spectre.Console.ProgressContext]$Context)

        $script:CurrentProgressContext = $Context
        $script:ProgressTasks = @{}
        try {
            & $script:ActiveScopeScriptBlock $Context
        }
        finally {
            $script:CurrentProgressContext = $null
            $script:ProgressTasks = @{}
            $script:ActiveScopeScriptBlock = $null
        }
    }

    return Invoke-SpectreCommandWithProgress -ScriptBlock $wrapped
}

function Read-SelectionSpectre {
    param(
        [object[]]$Items,
        [PSCustomObject[]]$Choices,
        [string]$Message,
        [int]$PageSize
    )

    $selected = @(Read-SpectreMultiSelection -Message $Message `
            -Choices $Choices `
            -ChoiceLabelProperty 'Label' `
            -PageSize $PageSize `
            -AllowEmpty)

    return @(
        foreach ($selection in $selected) {
            # Spectre renvoie soit l'objet de choix (propriété Value), soit le
            # simple libellé selon les versions : ne pas supposer que .Value
            # existe, sinon l'appelant reçoit des valeurs nulles.
            $valueProperty = $selection.PSObject.Properties['Value']

            if ($null -ne $valueProperty) {
                $valueProperty.Value
                continue
            }

            $matchingChoice = @($Choices | Where-Object { $_.Label -eq [string]$selection } | Select-Object -First 1)

            if ($matchingChoice.Count -eq 1) {
                $matchingChoice[0].Value
            }
            else {
                Write-StatusMessage "Ignored unknown selection: $selection" -Type Warning
            }
        }
    )
}
