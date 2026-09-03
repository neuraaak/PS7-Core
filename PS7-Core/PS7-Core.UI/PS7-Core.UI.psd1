@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'PS7-Core.UI.psm1'

    # Version number of this module.
    ModuleVersion     = '1.1.0'

    # ID used to uniquely identify this module
    GUID              = 'd55fbb76-a581-4783-8f86-4ff3f74d42db'

    # Author of this module
    Author            = 'Neuraaak'

    # Company or vendor of this module
    CompanyName       = 'Neuraaak'

    # Copyright statement for this module
    Copyright         = '(c) 2026 Neuraaak. MIT License.'

    # Description of the functionality provided by this module
    Description       = 'Enhanced console UI built on Spectre.Console (PwshSpectreConsole). Requires PS7+ and PwshSpectreConsole.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module
    FunctionsToExport = @(
        'Initialize-EnhancedUI',
        'Write-StatusMessage',
        'Write-ProgressBar',
        'Start-ProgressScope',
        'Write-Header',
        'Write-Summary',
        'Read-Selection',
        'Read-FolderSelection'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @('UIContext')

    # Aliases to export from this module
    AliasesToExport   = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData       = @{
        PSData = @{
            Tags         = @('UI', 'Console', 'Spectre', 'Output', 'Color')
            LicenseUri   = ''
            ProjectUri   = ''
            ReleaseNotes = 'v2.0.0 - Spectre.Console-only, PSWriteColor/PS5 fallback removed.'
        }
    }
}
