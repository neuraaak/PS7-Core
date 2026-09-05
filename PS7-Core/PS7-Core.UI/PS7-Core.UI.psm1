<#
.SYNOPSIS
    Enhanced PowerShell UI module.

.DESCRIPTION
    Console output with two interchangeable backends:

      Spectre  PwshSpectreConsole - rendu riche, progression live.
      Native   PowerShell 7 pur, aucune dependance externe.

    Le backend est resolu UNE FOIS par Initialize-EnhancedUI, jamais par appel :
    le choix depend de l'environnement, pas du site d'appel. Les fonctions
    publiques n'exposent donc aucun parametre de backend, et le code appelant
    est identique dans les deux modes.

    Les deux implementations sont dot-sourcees au chargement, TOUJOURS : definir
    les fonctions Spectre ne coute rien sans la lib installee, et cela permet de
    forcer le backend natif depuis une machine ou Spectre est present - sans
    quoi le chemin natif ne serait testable nulle part.

.NOTES
    Author:  Neuraaak
    Version: 1.2.0
    License: MIT
#>

#region Module Variables

# UI context stores the current UI provider information
$script:UIContext = @{
    UseSpectreConsole = $false
    Backend           = 'None'
    Initialized       = $false
}

# Set while inside a Spectre Start-ProgressScope; $null otherwise (always $null
# with the native backend, which has no live region).
$script:CurrentProgressContext = $null

# Activity name -> Spectre.Console.ProgressTask, only populated while
# $script:CurrentProgressContext is set.
$script:ProgressTasks = @{}

# The user scriptblock passed to Start-ProgressScope, while it is running.
# $null otherwise. See Start-ProgressScopeSpectre for why this is a module
# variable rather than a closure capture.
$script:ActiveScopeScriptBlock = $null

# Nesting sentinel, set by BOTH backends: the native scope opens no Spectre
# context, so $script:CurrentProgressContext cannot be used to detect nesting.
$script:InProgressScope = $false

# The "falling back to native" notice is emitted once per session, not per call.
$script:FallbackNoticeShown = $false

#endregion


#region Backend Loading

. (Join-Path $PSScriptRoot 'Spectre\Spectre.ps1')
. (Join-Path $PSScriptRoot 'Native\Native.ps1')

#endregion


#region Public Functions

<#
.SYNOPSIS
    Initializes the enhanced UI system and resolves the output backend.

.DESCRIPTION
    Enables VT100 processing and UTF-8 output, then selects a backend.

    'Auto' uses Spectre when PwshSpectreConsole can be imported and falls back
    to the native backend otherwise, announcing the fallback once so the
    degradation is never silent. 'Spectre' throws if the module is missing -
    an explicit request must fail loudly rather than degrade. 'Native' forces
    the dependency-free backend even where Spectre is available, which is how
    the native path is exercised by the test suite.

.PARAMETER Backend
    Auto (default), Spectre, or Native. Passing this parameter re-resolves the
    backend even if the UI was already initialized.

.EXAMPLE
    Initialize-EnhancedUI

.EXAMPLE
    Initialize-EnhancedUI -Backend Native
    Forces the native backend, e.g. to test it on a machine that has Spectre.

.OUTPUTS
    Hashtable containing UI context information.
#>
function Initialize-EnhancedUI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('Auto', 'Spectre', 'Native')]
        [string]$Backend = 'Auto'
    )

    $backendRequested = $PSBoundParameters.ContainsKey('Backend')

    if ($script:UIContext.Initialized -and -not $backendRequested) {
        Write-Verbose "UI already initialized (backend: $($script:UIContext.Backend))."
        return $script:UIContext
    }

    if (-not $script:UIContext.Initialized) {
        Initialize-ConsoleHostNative
    }

    switch ($Backend) {
        'Native' {
            $script:UIContext.UseSpectreConsole = $false
        }
        'Spectre' {
            if (-not (Test-SpectreAvailable)) {
                throw "Backend 'Spectre' was requested but PwshSpectreConsole is not installed. Install it with: Install-Module -Name PwshSpectreConsole -Scope CurrentUser"
            }
            $script:UIContext.UseSpectreConsole = $true
        }
        default {
            if (Test-SpectreAvailable) {
                $script:UIContext.UseSpectreConsole = $true
            }
            else {
                $script:UIContext.UseSpectreConsole = $false

                # Never degrade silently: say it once, then stay quiet.
                if (-not $script:FallbackNoticeShown) {
                    $script:FallbackNoticeShown = $true
                    Write-Host "PwshSpectreConsole not found - using the native display backend." -ForegroundColor DarkGray
                }
            }
        }
    }

    $script:UIContext.Backend = if ($script:UIContext.UseSpectreConsole) { 'Spectre' } else { 'Native' }
    $script:UIContext.Initialized = $true

    Write-Verbose "UI initialized: backend=$($script:UIContext.Backend)"

    return $script:UIContext
}


<#
.SYNOPSIS
    Returns the current UI context (backend, initialization state).

.DESCRIPTION
    Export-ModuleMember -Variable does NOT cross the nested-module boundary:
    when PS7-Core.UI is loaded as a nested module of PS7-Core, $UIContext is
    never published to the caller. A function is the only reliable way to read
    the context through that boundary, so prefer this over the variable.

.EXAMPLE
    if ((Get-UIContext).Backend -eq 'Native') { ... }

.OUTPUTS
    Hashtable. Keys: Backend, UseSpectreConsole, Initialized.
#>
function Get-UIContext {
    [CmdletBinding()]
    param ()

    return $script:UIContext
}


<#
.SYNOPSIS
    Runs a scriptblock inside a progress scope.

.DESCRIPTION
    With the Spectre backend, wraps Invoke-SpectreCommandWithProgress: while the
    scriptblock runs, Write-ProgressBar and Write-StatusMessage route through
    Spectre's live renderer, so a progress bar and a heavy stream of status
    messages coexist without corrupting the console.

    With the native backend there is no live region to open - Write-ProgressBar
    uses Write-Progress directly, which holds up under print load. The scope is
    still a REAL scope, invoked through '&' exactly like the Spectre one, so the
    child-scope pitfall below behaves identically in both backends: a script
    validated on one backend behaves the same on the other.

    Does not support nesting, in either backend.

    IMPORTANT (child scope): the scriptblock runs in a new child scope. Any
    variable reassigned inside it (=, +=, ++) creates a hidden local copy that is
    lost on exit. Mutating a member of an existing object ($table[$k] = $v,
    $list.Add(...)) is fine. To accumulate, use
    [System.Collections.Generic.List[object]] and .Add() rather than += on an array.

    Interactive prompts (Read-Selection, Read-FolderSelection) must run OUTSIDE
    any scope: Spectre cannot nest two live regions.

.PARAMETER ScriptBlock
    The work to run. Receives one positional argument: the active
    [Spectre.Console.ProgressContext] with the Spectre backend, $null with the
    native one. Most callers do not need it - Write-ProgressBar picks it up.

.EXAMPLE
    Start-ProgressScope -ScriptBlock {
        for ($i = 1; $i -le $total; $i++) {
            Write-ProgressBar -Activity "Scanning" -Current $i -Total $total
        }
        Write-ProgressBar -Activity "Scanning" -Completed
    }
#>
function Start-ProgressScope {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    if ($script:InProgressScope) {
        throw "Start-ProgressScope does not support nesting."
    }

    $script:InProgressScope = $true
    try {
        if ($script:UIContext.UseSpectreConsole) {
            return Start-ProgressScopeSpectre -ScriptBlock $ScriptBlock
        }
        return Start-ProgressScopeNative -ScriptBlock $ScriptBlock
    }
    finally {
        $script:InProgressScope = $false
        $script:CurrentProgressContext = $null
        $script:ProgressTasks = @{}
        $script:ActiveScopeScriptBlock = $null
    }
}


<#
.SYNOPSIS
    Writes colored status messages through the active backend.

.PARAMETER Message
    The message to display.

.PARAMETER Type
    The message type. Valid values: Info, Success, Warning, Error, Skipped, Debug.

.EXAMPLE
    Write-StatusMessage "Operation completed" -Type Success
#>
function Write-StatusMessage {
    [CmdletBinding()]
    param (
        # AllowNull + AllowEmptyString : sans eux, passer $null a un parametre
        # Mandatory ne leve PAS, PowerShell ouvre une invite interactive et le
        # script se fige indefiniment. Pour une fonction d'affichage, un blocage
        # est le pire resultat possible : on accepte, et on imprime une ligne vide.
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Skipped', 'Debug')]
        [string]$Type = 'Info'
    )

    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    if ($script:UIContext.UseSpectreConsole) {
        Write-StatusMessageSpectre -Message $Message -Type $Type
    }
    else {
        Write-StatusMessageNative -Message $Message -Type $Type
    }
}


<#
.SYNOPSIS
    Displays a progress indicator for operations.

.DESCRIPTION
    Inside a Spectre progress scope, drives a task of the live ProgressContext
    (one per distinct Activity). Everywhere else - native backend, or outside any
    scope - uses native Write-Progress, which occupies a dedicated terminal
    region and never pollutes the text stream.

.PARAMETER Activity
    The activity description.

.PARAMETER Current
    The current item number being processed.

.PARAMETER Total
    The total number of items to process.

.PARAMETER Status
    Additional status information to display.

.PARAMETER Id
    The progress bar ID for nested progress bars (native rendering only).

.PARAMETER ParentId
    The parent progress bar ID for nested progress bars (native rendering only).

.PARAMETER Completed
    Switch to indicate the operation is completed and the bar should be removed.

.EXAMPLE
    Write-ProgressBar -Activity "Processing files" -Current 50 -Total 100
#>
function Write-ProgressBar {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Activity,

        [Parameter(Mandatory = $false)]
        [int]$Current = 0,

        [Parameter(Mandatory = $false)]
        [int]$Total = 100,

        [Parameter(Mandatory = $false)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [int]$Id = 0,

        [Parameter(Mandatory = $false)]
        [int]$ParentId = -1,

        [Parameter(Mandatory = $false)]
        [switch]$Completed
    )

    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    # Dispatch on the live context, not on the backend: the native backend never
    # sets one, so it always lands on Write-Progress.
    if ($null -ne $script:CurrentProgressContext) {
        Write-ProgressBarSpectre -Activity $Activity -Current $Current -Total $Total -Status $Status -Completed:$Completed
        return
    }

    Write-ProgressBarNative -Activity $Activity -Current $Current -Total $Total -Status $Status -Id $Id -ParentId $ParentId -Completed:$Completed
}


<#
.SYNOPSIS
    Displays a formatted header.

.DESCRIPTION
    A Spectre Rule with the Spectre backend; a plain horizontal rule built from
    box-drawing characters with the native one. The native rendering is
    deliberately poorer - matching Spectre pixel for pixel is not the goal.

.PARAMETER Title
    The header title.

.PARAMETER Color
    The header color.

.EXAMPLE
    Write-Header "My Application"
#>
function Write-Header {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [string]$Color = 'Cyan'
    )

    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    if ($script:UIContext.UseSpectreConsole) {
        Write-HeaderSpectre -Title $Title -Color $Color
    }
    else {
        Write-HeaderNative -Title $Title -Color $Color
    }

    Write-Host ""
}


<#
.SYNOPSIS
    Displays a formatted summary section.

.PARAMETER Title
    The summary title (default: "Summary").

.EXAMPLE
    Write-Summary
    Write-StatusMessage "Total: 100" -Type Info
#>
function Write-Summary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Title = 'Summary'
    )

    Write-Host ""
    Write-Header $Title -Color Green
}


<#
.SYNOPSIS
    Prompts the user to pick a subset of items.

.DESCRIPTION
    With the Spectre backend, shows a checkbox list (Read-SpectreMultiSelection).
    With the native backend - or when the Spectre prompt itself throws at runtime
    - shows a numbered text prompt: "1,3,5", "*" for all, empty for none. Both
    return the selected items with their original type preserved.

    The prompt needs a real console. When input is redirected (scheduled task,
    piped invocation), no prompt can be shown: the function warns and returns
    every item unchanged, so callers behave as if no filtering was requested.

.PARAMETER Items
    The items to choose from. Returned as-is, so any type is preserved.

.PARAMETER Message
    The prompt title.

.PARAMETER LabelProperty
    Name of the property used to label each item. Defaults to its string form.

.PARAMETER PageSize
    Number of entries shown at once by the Spectre prompt.

.EXAMPLE
    $keep = Read-Selection -Items $folders -Message "Folders to process"
#>
function Read-Selection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [Parameter(Mandatory = $false)]
        [string]$Message = 'Select the entries to keep',

        [Parameter(Mandatory = $false)]
        [string]$LabelProperty,

        [Parameter(Mandatory = $false)]
        [int]$PageSize = 15
    )

    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    if ($Items.Count -eq 0) {
        return @()
    }

    # No console to prompt on: keep everything rather than silently dropping items
    if ([Console]::IsInputRedirected) {
        Write-StatusMessage "Input is redirected, interactive selection skipped: all $($Items.Count) entrie(s) kept." -Type Warning
        return $Items
    }

    # Wrap each item so the prompt shows a label while we return the original object
    $choices = @(
        foreach ($item in $Items) {
            $label = if ($LabelProperty) { [string]$item.$LabelProperty } else { [string]$item }

            [PSCustomObject]@{
                Label = $label
                Value = $item
            }
        }
    )

    if ($script:UIContext.UseSpectreConsole) {
        try {
            return Read-SelectionSpectre -Items $Items -Choices $choices -Message $Message -PageSize $PageSize
        }
        catch {
            Write-StatusMessage "Interactive prompt failed, falling back to text mode - $($_.Exception.Message)" -Type Warning
        }
    }

    return Read-SelectionNative -Items $Items -Choices $choices -Message $Message
}



<#
.SYNOPSIS
    Scans a root folder's direct subfolders, then prompts the user to pick which to keep.

.DESCRIPTION
    Candidates are each of the root folder's direct subfolders, never the root
    folder itself and never any deeper descendant. Any candidate whose name
    matches -ExcludeName (case-insensitive) is left out entirely — this is how
    callers keep a folder they don't want offered (an already-processed
    destination folder, a working/output folder, etc.) out of the list.

    Without -Interactive, every candidate is returned unfiltered. With
    -Interactive, Read-Selection shows a checkbox prompt (falling back to a
    numbered text prompt if the interactive one fails) and only the ticked
    folders are returned.

.PARAMETER Path
    The root folder to scan. Must exist.

.PARAMETER ExcludeName
    Direct-subfolder names to exclude from the candidates, case-insensitive.

.PARAMETER Interactive
    Show the checkbox prompt. Without it, all candidates are returned as-is.

.PARAMETER Message
    The prompt title, used only when -Interactive is set.

.PARAMETER PageSize
    Number of entries shown at once by the Spectre prompt.

.OUTPUTS
    String[]. Full paths of the selected direct subfolders.

.EXAMPLE
    $folders = Read-FolderSelection -Path 'C:\Projects' -ExcludeName '.git', 'node_modules' -Interactive
    Scan the direct subfolders of C:\Projects, skip any named .git or
    node_modules, and let the user tick which ones to keep.
#>
function Read-FolderSelection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeName = @(),

        [Parameter(Mandatory = $false)]
        [switch]$Interactive,

        [Parameter(Mandatory = $false)]
        [string]$Message = 'Folders to process',

        [Parameter(Mandatory = $false)]
        [int]$PageSize = 15
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Path not found or not a directory: $Path"
    }

    $rootFolder = Get-Item -LiteralPath $Path -Force
    $excludeSet = @($ExcludeName | ForEach-Object { $_.ToLower() })

    $candidates = @()

    foreach ($sub in @(Get-ChildItem -LiteralPath $rootFolder.FullName -Directory -ErrorAction SilentlyContinue)) {
        if ($excludeSet -contains $sub.Name.ToLower()) {
            continue
        }

        $candidates += [PSCustomObject]@{
            Path  = $sub.FullName
            Label = $sub.Name
        }
    }

    if (-not $Interactive) {
        return @($candidates | ForEach-Object { $_.Path })
    }

    $selected = @(Read-Selection -Items $candidates -Message $Message -LabelProperty 'Label' -PageSize $PageSize)
    return @($selected | ForEach-Object { $_.Path })
}

#endregion


#region Module Initialization

# Export module members
Export-ModuleMember -Function @(
    'Initialize-EnhancedUI',
    'Get-UIContext',
    'Write-StatusMessage',
    'Write-ProgressBar',
    'Start-ProgressScope',
    'Write-Header',
    'Write-Summary',
    'Read-Selection',
    'Read-FolderSelection'
) -Variable @(
    'UIContext'
)

#endregion
