<#
.SYNOPSIS
    Enhanced PowerShell UI module.

.DESCRIPTION
    This module provides enhanced console output built on Spectre.Console
    (PwshSpectreConsole). PS7+ and PwshSpectreConsole are required; the toolset
    is PS7-only by design and does not fall back to a degraded provider.

.NOTES
    Author:  Neuraaak
    Version: 2.0.0
    License: MIT
#>

#region Module Variables

# UI context stores the current UI provider information
$script:UIContext = @{
    UseSpectreConsole = $false
    Initialized       = $false
}

# Set while inside Start-ProgressScope; $null otherwise.
$script:CurrentProgressContext = $null

# Activity name -> Spectre.Console.ProgressTask, only populated while
# $script:CurrentProgressContext is set.
$script:ProgressTasks = @{}

# The user scriptblock passed to Start-ProgressScope, while it is running.
# $null otherwise. See Start-ProgressScope for why this is a module variable
# rather than a closure capture.
$script:ActiveScopeScriptBlock = $null

#endregion


#region Public Functions

<#
.SYNOPSIS
    Initializes the enhanced UI system with automatic provider detection.

.DESCRIPTION
    Loads PwshSpectreConsole and enables VT100 processing on the console.
    Throws a terminating error if PwshSpectreConsole is not installed —
    this toolset requires it, it is not auto-installed.

.EXAMPLE
    Initialize-EnhancedUI
    Initializes UI with default settings.

.OUTPUTS
    Hashtable containing UI context information.
#>
function Initialize-EnhancedUI {
    [CmdletBinding()]
    param ()

    if ($script:UIContext.Initialized) {
        Write-Verbose "UI already initialized."
        return $script:UIContext
    }

    # Legacy conhost (e.g. a .cmd double-clicked from Explorer) does not enable
    # VT100/ANSI processing by default, which makes Spectre.Console's interactive
    # prompts (Read-SpectreMultiSelection) throw and silently fall back to plain text.
    if ($env:OS -eq 'Windows_NT') {
        try {
            $signature = @'
[DllImport("kernel32.dll")] public static extern bool GetStdHandle(int handle, out System.IntPtr result);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr handle, out int mode);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr handle, int mode);
'@
            $type = Add-Type -MemberDefinition $signature -Name 'ConsoleVT' -Namespace 'PS7-Core.UI' -PassThru -ErrorAction Stop

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

    # Set console encoding to UTF-8 for emoji support
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
    }
    catch {
        Write-Verbose "Failed to set UTF-8 encoding: $_"
    }

    if (-not (Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)) {
        if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }
    }

    if (-not (Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)) {
        throw "PwshSpectreConsole is required but not installed. Install it with: Install-Module -Name PwshSpectreConsole -Scope CurrentUser"
    }

    $script:UIContext.UseSpectreConsole = $true
    $script:UIContext.Initialized = $true

    Write-Verbose "UI initialized: Spectre=$($script:UIContext.UseSpectreConsole)"

    return $script:UIContext
}


<#
.SYNOPSIS
    Runs a scriptblock inside a Spectre.Console live progress region.

.DESCRIPTION
    Wraps Invoke-SpectreCommandWithProgress (PwshSpectreConsole). While the
    scriptblock runs, Write-ProgressBar and Write-StatusMessage automatically
    route through Spectre's live renderer instead of native Write-Progress /
    Write-SpectreHost, so a progress bar and a heavy stream of status
    messages can coexist without corrupting the console.

    Does not support nesting: Spectre cannot render one Live region inside
    another. Interactive prompts (Read-Selection, Read-FolderSelection) must
    run outside any Start-ProgressScope call.

    An exception thrown inside the scriptblock surfaces to the caller wrapped
    by Invoke-SpectreCommandWithProgress's own exception handling, which loses
    the original ErrorRecord's category/type info — a caller matching on
    exception type around Start-ProgressScope should be aware of this.

.PARAMETER ScriptBlock
    The work to run. Receives one positional argument, the active
    [Spectre.Console.ProgressContext] — most callers do not need it
    directly since Write-ProgressBar picks it up automatically.

.EXAMPLE
    Start-ProgressScope -ScriptBlock {
        for ($i = 1; $i -le $total; $i++) {
            Write-ProgressBar -Activity "Scanning" -Current $i -Total $total
            Write-StatusMessage "Processed file $i" -Type Info
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

    if ($null -ne $script:CurrentProgressContext) {
        throw "Start-ProgressScope does not support nesting."
    }

    # Note: deliberately NOT using .GetNewClosure() here. Spectre invokes this
    # scriptblock from deep inside its own callback (via Progress.Start()), and
    # GetNewClosure() would detach the scriptblock into a private copy of the
    # module's $script: variables — writes to $script:CurrentProgressContext
    # inside the closure would then be invisible to Write-ProgressBar /
    # Write-StatusMessage, which read the real module scope (verified empirically:
    # the closure saw its own write, but the rest of the module still saw $null).
    # A plain scriptblock literal defined in this .psm1 already resolves $script:
    # to the module's scope regardless of the call stack it's invoked from, so we
    # stash the user scriptblock in a module variable instead of a closure capture.
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


<#
.SYNOPSIS
    Writes colored status messages using the best available output method.

.DESCRIPTION
    Displays messages with appropriate coloring based on message type, using
    Spectre.Console.

.PARAMETER Message
    The message to display.

.PARAMETER Type
    The message type. Valid values: Info, Success, Warning, Error, Skipped, Debug.

.EXAMPLE
    Write-StatusMessage "Operation completed" -Type Success

.EXAMPLE
    Write-StatusMessage "File not found" -Type Error
#>
function Write-StatusMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Skipped', 'Debug')]
        [string]$Type = 'Info'
    )

    # Ensure UI is initialized
    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    # Use Spectre.Console if available (PS7+).
    # Markup is required for color — Write-SpectreHost without [tags] is plain text.
    # We escape user content's [ and ] to avoid breaking the markup parser.
    if ($script:UIContext.UseSpectreConsole) {
        $safe = $Message -replace '\[', '[[' -replace '\]', ']]'
        $markup = switch ($Type) {
            'Info' { "[cyan]$safe[/]" }
            'Success' { "[green]OK:[/] $safe" }
            'Warning' { "[yellow]WARN:[/] $safe" }
            'Error' { "[red]ERROR:[/] $safe" }
            'Skipped' { "[grey]SKIP:[/] $safe" }
            'Debug' { "[grey]DEBUG:[/] $safe" }
        }

        if ($null -ne $script:CurrentProgressContext) {
            # Write-SpectreHost glitches when called from inside a live Spectre
            # progress region (verified manually, see Start-ProgressScope docs);
            # AnsiConsole.MarkupLine does not.
            [Spectre.Console.AnsiConsole]::MarkupLine($markup)
        }
        else {
            Write-SpectreHost $markup
        }
    }
}


<#
.SYNOPSIS
    Displays a progress indicator for operations.

.DESCRIPTION
    Shows progress using native Write-Progress.

.PARAMETER Activity
    The activity description.

.PARAMETER Current
    The current item number being processed.

.PARAMETER Total
    The total number of items to process.

.PARAMETER Status
    Additional status information to display.

.PARAMETER Id
    The progress bar ID for nested progress bars (used with standard Write-Progress).

.PARAMETER ParentId
    The parent progress bar ID for nested progress bars (used with standard Write-Progress).

.PARAMETER Completed
    Switch to indicate the operation is completed and the progress bar should be removed.

.EXAMPLE
    Write-ProgressBar -Activity "Processing files" -Current 50 -Total 100

.EXAMPLE
    Write-ProgressBar -Activity "Processing files" -Current 50 -Total 100 -Status "file.txt"

.EXAMPLE
    Write-ProgressBar -Activity "Processing files" -Completed
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

    # Ensure UI is initialized
    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    if ($null -ne $script:CurrentProgressContext) {
        # Inside Start-ProgressScope: render via Spectre's live ProgressContext,
        # one task per distinct Activity, so bar + Write-StatusMessage logs
        # coexist without corrupting the console (native Write-Progress can,
        # under heavy print volume — see Start-ProgressScope docs).
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
        return
    }

    # Handle completion
    if ($Completed) {
        Write-Progress -Activity $Activity -Id $Id -Completed
        return
    }

    # Always delegate to native Write-Progress.
    # Reasons:
    #   - Write-SpectreHost does not honor -NoNewline reliably across versions,
    #     so a custom inline progress bar collides with subsequent Write-Host calls
    #     (status lines like "RENAMED:" end up glued to "Processing: file.jpg").
    #   - Native Write-Progress uses a dedicated terminal region and never pollutes
    #     the text output stream.
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


<#
.SYNOPSIS
    Displays a formatted header.

.DESCRIPTION
    Shows a prominent header using a Spectre.Console Rule.

.PARAMETER Title
    The header title.

.PARAMETER Color
    The header color (Spectre.Console color name).

.EXAMPLE
    Write-Header "My Application"

.EXAMPLE
    Write-Header "Processing Complete" -Color Green
#>
function Write-Header {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [string]$Color = 'Cyan'
    )

    # Ensure UI is initialized
    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    try {
        Write-SpectreRule -Title $Title -Color $Color
    }
    catch {
        Write-SpectreHost $Title
    }
    Write-Host ""
}


<#
.SYNOPSIS
    Displays a formatted summary section.

.DESCRIPTION
    Shows a summary header similar to Write-Header but optimized for result display.

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
    Prompts the user to pick a subset of items with a checkbox list.

.DESCRIPTION
    Displays an interactive multi-selection prompt and returns the selected
    items, preserving their original type.

    Uses Read-SpectreMultiSelection for a checkbox list. If Spectre's prompt
    throws (e.g. a non-interactive terminal it couldn't detect via redirected
    streams), falls back to a numbered text prompt: "1,3,5", "*" for all,
    empty for none.

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
    Ask which folders to keep, and get the selected DirectoryInfo objects back.

.EXAMPLE
    $keep = Read-Selection -Items $targets -LabelProperty 'Label'
    Label each entry with its Label property instead of its string form.
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

    # Ensure UI is initialized
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

    try {
        $selected = @(Read-SpectreMultiSelection -Message $Message `
                -Choices $choices `
                -ChoiceLabelProperty 'Label' `
                -PageSize $PageSize `
                -AllowEmpty)

        return @(
            foreach ($selection in $selected) {
                $valueProperty = $selection.PSObject.Properties['Value']

                if ($null -ne $valueProperty) {
                    $valueProperty.Value
                    continue
                }

                $matchingChoice = @($choices | Where-Object { $_.Label -eq [string]$selection } | Select-Object -First 1)

                if ($matchingChoice.Count -eq 1) {
                    $matchingChoice[0].Value
                }
                else {
                    Write-StatusMessage "Ignored unknown selection: $selection" -Type Warning
                }
            }
        )
    }
    catch {
        Write-StatusMessage "Interactive prompt failed, falling back to text mode - $($_.Exception.Message)" -Type Warning
    }

    # Text fallback when the Spectre prompt itself fails at runtime
    Write-Host ""
    Write-StatusMessage $Message -Type Info

    for ($i = 0; $i -lt $choices.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $choices[$i].Label)
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

        if ([int]::TryParse($token, [ref]$index) -and $index -ge 1 -and $index -le $choices.Count) {
            $picked += $choices[$index - 1].Value
        }
        else {
            Write-StatusMessage "Ignored invalid entry: $token" -Type Warning
        }
    }

    return @($picked)
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
