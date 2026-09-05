@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'PS7-Core.psm1'

    # Version number of this module.
    ModuleVersion     = '1.2.0'

    # ID used to uniquely identify this module
    GUID              = '2dc68349-bad7-414e-aff0-b0e58bf64d47'

    # Author of this module
    Author            = 'Neuraaak'

    # Company or vendor of this module
    CompanyName       = 'Neuraaak'

    # Copyright statement for this module
    Copyright         = '(c) 2026 Neuraaak. MIT License.'

    # Description of the functionality provided by this module
    Description       = 'PS7-Core - Complete suite of PowerShell utilities including runtime management, enhanced UI, and cryptographic functions. PS7+ only.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Modules that must be imported into the global environment prior to importing this module
    NestedModules     = @(
        'PS7-Core.Runtime\PS7-Core.Runtime.psd1',
        'PS7-Core.UI\PS7-Core.UI.psd1',
        'PS7-Core.Crypto\PS7-Core.Crypto.psd1'
    )

    # Functions to export from this module (imported from nested modules)
    FunctionsToExport = @(
        # PS7-Core.Runtime
        'Assert-PowerShell7',

        # PS7-Core.UI
        'Initialize-EnhancedUI',
        'Get-UIContext',
        'Write-StatusMessage',
        'Write-ProgressBar',
        'Start-ProgressScope',
        'Write-Header',
        'Write-Summary',
        'Read-Selection',
        'Read-FolderSelection',

        # PS7-Core.Crypto
        'Get-FileHashExtended',
        'Get-StringHash',
        'Test-FileIntegrity'
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
            Tags         = @('PowerShell', 'Utilities', 'UI', 'Crypto', 'Runtime', 'Core')
            LicenseUri   = ''
            ProjectUri   = ''
            ReleaseNotes = @'
v1.1.0 - PS7-only
- PS7-Core.Runtime: Assert-PowerShell7 guard (re-invocation logic removed)
- PS7-Core.UI: Enhanced console UI built on Spectre.Console only
- PS7-Core.Crypto: Cryptographic hashing for files and strings
'@
        }
    }
}
