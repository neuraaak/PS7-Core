@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'PS7-Core.UI.psm1'

    # Version number of this module. Single source of truth for the whole
    # library: the four manifests move together. The submodules never ship on
    # their own — the junction targets the parent and consumers import PS7-Core —
    # so a version of their own would inform nobody and drift instead.
    ModuleVersion     = '1.4.0'

    # ID used to uniquely identify this module
    GUID              = 'd55fbb76-a581-4783-8f86-4ff3f74d42db'

    # Author of this module
    Author            = 'Neuraaak'

    # Company or vendor of this module
    CompanyName       = 'Neuraaak'

    # Copyright statement for this module
    Copyright         = '(c) 2026 Neuraaak. MIT License.'

    # Description of the functionality provided by this module
    Description       = 'Enhanced console UI with two interchangeable backends: Spectre (PwshSpectreConsole) and Native (pure PowerShell 7, no external dependency). Requires PS7+; PwshSpectreConsole is optional.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module
    FunctionsToExport = @(
        'Initialize-EnhancedUI',
        'Get-UIContext',
        'Write-StatusMessage',
        'Write-ProgressBar',
        'Start-ProgressScope',
        'Write-Header',
        'Write-Summary',
        'Read-Selection',
        'Read-FolderSelection',
        'Read-Confirmation',
        'Read-TextInput',
        'Start-Spinner'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module. Deliberately empty: Export-ModuleMember
    # -Variable does not cross the nested-module boundary, so declaring $UIContext
    # here promised an export that never materialised. Get-UIContext is the access.
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData       = @{
        PSData = @{
            Tags       = @('UI', 'Console', 'Spectre', 'Native', 'Output', 'Color')
            LicenseUri = ''
            ProjectUri = ''
        }
    }
}
