@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'PS7-Core.Crypto.psm1'

    # Version number of this module.
    ModuleVersion     = '1.0.0'

    # ID used to uniquely identify this module
    GUID              = '8136eda9-92ca-4a3f-a478-8382dbb14b21'

    # Author of this module
    Author            = 'Neuraaak'

    # Company or vendor of this module
    CompanyName       = 'Neuraaak'

    # Copyright statement for this module
    Copyright         = '(c) 2026 Neuraaak. MIT License.'

    # Description of the functionality provided by this module
    Description       = 'Cryptographic utilities for file hashing with support for SHA256, SHA1, and MD5 algorithms.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module
    FunctionsToExport = @(
        'Get-FileHashExtended',
        'Get-StringHash',
        'Test-FileIntegrity'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData       = @{
        PSData = @{
            Tags         = @('Crypto', 'Hash', 'SHA256', 'MD5', 'Security')
            LicenseUri   = ''
            ProjectUri   = ''
            ReleaseNotes = 'Initial release with file and string hashing capabilities.'
        }
    }
}
