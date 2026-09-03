<#
.SYNOPSIS
    PS7-Core - Complete PowerShell utilities suite.

.DESCRIPTION
    Meta-module that loads all PS7-Core submodules for convenient one-line import.
    This module provides a unified interface to:
    - PS7-Core.Runtime: PowerShell version management
    - PS7-Core.UI: Enhanced console user interface
    - PS7-Core.Crypto: Cryptographic utilities

.NOTES
    Author:  Neuraaak
    Version: 1.0.0
    License: MIT

.EXAMPLE
    Import-Module PS7-Core
    # Imports all PS7-Core modules at once
#>

# This is a meta-module that simply loads all nested modules
# All functionality is provided by the nested modules defined in the .psd1 file

# Display welcome message (optional, can be removed if too verbose)
Write-Verbose "PS7-Core modules loaded successfully"
Write-Verbose "  - PS7-Core.Runtime"
Write-Verbose "  - PS7-Core.UI"
Write-Verbose "  - PS7-Core.Crypto"
