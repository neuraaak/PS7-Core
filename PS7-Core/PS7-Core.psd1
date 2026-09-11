@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'PS7-Core.psm1'

    # Version number of this module. Single source of truth for the whole
    # library: the four manifests move together. The submodules never ship on
    # their own — the junction targets the parent and consumers import PS7-Core —
    # so a version of their own would inform nobody and drift instead.
    ModuleVersion     = '1.4.0'

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
        'Initialize-Logging',
        'Write-Log',
        'Get-LogContext',

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
        'Read-Confirmation',
        'Read-TextInput',
        'Start-Spinner',

        # PS7-Core.Crypto
        'Get-FileHashExtended',
        'Get-StringHash',
        'Test-FileIntegrity'
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
            Tags         = @('PowerShell', 'Utilities', 'UI', 'Crypto', 'Runtime', 'Core')
            LicenseUri   = ''
            ProjectUri   = ''
            # Cumulative history for the whole library. The submodule manifests
            # carry none: one version, one changelog.
            ReleaseNotes = @'
1.3.0
- PS7-Core.Runtime : logging fichier opt-in (Initialize-Logging, Write-Log,
  Get-LogContext). Aucune dependance ajoutee, rien n'est ecrit sans appel
  explicite a Initialize-Logging.
- PS7-Core.UI : Write-StatusMessage et Write-Header alimentent le log quand
  il est actif. Write-ProgressBar volontairement exclu.

v1.2.1
- PS7-Core.Crypto: Get-FileHashExtended now resolves paths literally; a name
  containing brackets ('copie[1].txt') was reported as not found.
- PS7-Core.Crypto: covered by the test suite, previously untested.
- PS7-Core.UI: $UIContext is no longer declared as an exported variable - the
  export never crossed the nested-module boundary. Use Get-UIContext.
- Single version across the four manifests.

v1.2.0
- PS7-Core.UI: interchangeable Spectre / Native backends, resolved once by
  Initialize-EnhancedUI. PwshSpectreConsole is now optional.

v1.1.0 - PS7-only
- PS7-Core.Runtime: Assert-PowerShell7 guard (re-invocation logic removed)
- PS7-Core.UI: Enhanced console UI built on Spectre.Console
- PS7-Core.Crypto: Cryptographic hashing for files and strings
'@
        }
    }
}
