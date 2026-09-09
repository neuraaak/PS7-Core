<#
.SYNOPSIS
    PowerShell runtime guard module.

.DESCRIPTION
    This module provides a single guard function ensuring scripts run under
    PowerShell 7+. This toolset is PS7-only by design: PS7+ is expected to be
    installed and set as the default handler for .ps1 files.

.NOTES
    Author:  Neuraaak
    License: MIT
#>

#region Public Functions

<#
.SYNOPSIS
    Stops the script with a clear error if not running under PowerShell 7+.

.DESCRIPTION
    This toolset targets PowerShell 7+ only. Call this at the top of every
    entry-point script to fail fast with an actionable message instead of
    hitting unrelated errors further down (missing operators, cmdlets, etc.).

.PARAMETER MinimumVersion
    Minimum PowerShell version required. Default is 7.0.

.EXAMPLE
    Assert-PowerShell7
#>
function Assert-PowerShell7 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [version]$MinimumVersion = '7.0'
    )

    if ($PSVersionTable.PSVersion -ge $MinimumVersion) {
        return
    }

    throw "This script requires PowerShell $MinimumVersion or higher (currently running $($PSVersionTable.PSVersion)). Install PowerShell 7+ from https://aka.ms/powershell and set it as the default handler for .ps1 files."
}

#endregion


#region Module Initialization

# Export module members
Export-ModuleMember -Function @(
    'Assert-PowerShell7'
)

#endregion
