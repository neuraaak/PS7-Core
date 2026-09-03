@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'PS7-Core.Runtime.psm1'

    # Version number of this module.
    ModuleVersion     = '1.0.0'

    # ID used to uniquely identify this module
    GUID              = '90fe6b3c-f631-46b2-b72e-a6a5d790aa49'

    # Author of this module
    Author            = 'Neuraaak'

    # Company or vendor of this module
    CompanyName       = 'Neuraaak'

    # Copyright statement for this module
    Copyright         = '(c) 2026 Neuraaak. MIT License.'

    # Description of the functionality provided by this module
    Description       = 'PowerShell runtime guard ensuring scripts run under PowerShell 7+.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module
    FunctionsToExport = @('Assert-PowerShell7')

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData       = @{
        PSData = @{
            Tags         = @('PowerShell', 'Runtime', 'PS7', 'Core')
            LicenseUri   = ''
            ProjectUri   = ''
            ReleaseNotes = 'v2.0.0 - PS7-only guard (Assert-PowerShell7), re-invocation logic removed.'
        }
    }
}
