<#
.SYNOPSIS
    PowerShell cryptographic utilities module.

.DESCRIPTION
    This module provides cryptographic functions for file and string hashing
    with support for multiple algorithms (SHA256, SHA1, MD5).

.NOTES
    Author:  Neuraaak
    Version: 1.0.0
    License: MIT
#>

#region Public Functions

<#
.SYNOPSIS
    Calculates the cryptographic hash of a file.

.DESCRIPTION
    Computes the hash of a file using the specified algorithm (SHA256, SHA1, or MD5).
    Returns the hash as a lowercase hexadecimal string without separators.

.PARAMETER Path
    The full path to the file to hash.

.PARAMETER Algorithm
    The hash algorithm to use. Valid values: SHA256, SHA1, MD5.
    Default: SHA256

.PARAMETER UpperCase
    Return the hash in uppercase instead of lowercase.

.EXAMPLE
    Get-FileHashExtended -Path "C:\file.txt"
    Returns SHA256 hash in lowercase.

.EXAMPLE
    Get-FileHashExtended -Path "C:\file.txt" -Algorithm MD5 -UpperCase
    Returns MD5 hash in uppercase.

.OUTPUTS
    String containing the hash value, or $null on error.
#>
function Get-FileHashExtended {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('FilePath', 'FullName')]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('SHA256', 'SHA1', 'MD5')]
        [string]$Algorithm = 'SHA256',

        [Parameter(Mandatory = $false)]
        [switch]$UpperCase
    )

    process {
        $hashObject = $null
        $fileStream = $null

        try {
            # Validate file exists
            if (-not (Test-Path -Path $Path -PathType Leaf)) {
                Write-Error "File not found: $Path"
                return $null
            }

            # Create the appropriate hash algorithm object
            $hashObject = switch ($Algorithm) {
                'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
                'SHA1' { [System.Security.Cryptography.SHA1]::Create() }
                'MD5' { [System.Security.Cryptography.MD5]::Create() }
            }

            # Open file and compute hash
            $fileStream = [System.IO.File]::OpenRead($Path)
            $hashBytes = $hashObject.ComputeHash($fileStream)

            # Convert to hex string
            $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''

            # Return in requested case
            if ($UpperCase) {
                return $hashString
            }
            else {
                return $hashString.ToLower()
            }
        }
        catch {
            Write-Error "Failed to compute hash for $Path : $_"
            return $null
        }
        finally {
            # Clean up resources
            if ($fileStream) { $fileStream.Close() }
            if ($hashObject) { $hashObject.Dispose() }
        }
    }
}


<#
.SYNOPSIS
    Calculates the cryptographic hash of a string.

.DESCRIPTION
    Computes the hash of a string using the specified algorithm.

.PARAMETER String
    The string to hash.

.PARAMETER Algorithm
    The hash algorithm to use. Valid values: SHA256, SHA1, MD5.
    Default: SHA256

.PARAMETER Encoding
    The text encoding to use. Default: UTF8

.PARAMETER UpperCase
    Return the hash in uppercase instead of lowercase.

.EXAMPLE
    Get-StringHash -String "Hello World"

.EXAMPLE
    Get-StringHash -String "Password123" -Algorithm MD5

.OUTPUTS
    String containing the hash value.
#>
function Get-StringHash {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true
        )]
        [string]$String,

        [Parameter(Mandatory = $false)]
        [ValidateSet('SHA256', 'SHA1', 'MD5')]
        [string]$Algorithm = 'SHA256',

        [Parameter(Mandatory = $false)]
        [ValidateSet('UTF8', 'ASCII', 'Unicode', 'UTF32')]
        [string]$Encoding = 'UTF8',

        [Parameter(Mandatory = $false)]
        [switch]$UpperCase
    )

    process {
        $hashObject = $null

        try {
            # Create the appropriate hash algorithm object
            $hashObject = switch ($Algorithm) {
                'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
                'SHA1' { [System.Security.Cryptography.SHA1]::Create() }
                'MD5' { [System.Security.Cryptography.MD5]::Create() }
            }

            # Get encoder
            $encoder = switch ($Encoding) {
                'UTF8' { [System.Text.Encoding]::UTF8 }
                'ASCII' { [System.Text.Encoding]::ASCII }
                'Unicode' { [System.Text.Encoding]::Unicode }
                'UTF32' { [System.Text.Encoding]::UTF32 }
            }

            # Convert string to bytes and compute hash
            $stringBytes = $encoder.GetBytes($String)
            $hashBytes = $hashObject.ComputeHash($stringBytes)

            # Convert to hex string
            $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''

            # Return in requested case
            if ($UpperCase) {
                return $hashString
            }
            else {
                return $hashString.ToLower()
            }
        }
        catch {
            Write-Error "Failed to compute hash for string: $_"
            return $null
        }
        finally {
            # Clean up resources
            if ($hashObject) { $hashObject.Dispose() }
        }
    }
}


<#
.SYNOPSIS
    Verifies file integrity against a known hash.

.DESCRIPTION
    Computes the hash of a file and compares it against an expected hash value.

.PARAMETER Path
    The full path to the file to verify.

.PARAMETER ExpectedHash
    The expected hash value to compare against.

.PARAMETER Algorithm
    The hash algorithm to use. Valid values: SHA256, SHA1, MD5.
    Default: SHA256

.EXAMPLE
    Test-FileIntegrity -Path "C:\file.txt" -ExpectedHash "abc123..."

.EXAMPLE
    Test-FileIntegrity -Path "C:\file.txt" -ExpectedHash "def456..." -Algorithm MD5

.OUTPUTS
    Boolean indicating whether the file hash matches the expected hash.
#>
function Test-FileIntegrity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$ExpectedHash,

        [Parameter(Mandatory = $false)]
        [ValidateSet('SHA256', 'SHA1', 'MD5')]
        [string]$Algorithm = 'SHA256'
    )

    try {
        $actualHash = Get-FileHashExtended -Path $Path -Algorithm $Algorithm

        if (-not $actualHash) {
            Write-Error "Failed to compute hash for verification."
            return $false
        }

        # Normalize for comparison (case-insensitive)
        $actualHash = $actualHash.ToLower()
        $ExpectedHash = $ExpectedHash.ToLower()

        if ($actualHash -eq $ExpectedHash) {
            Write-Verbose "File integrity verified: Hash matches."
            return $true
        }
        else {
            Write-Warning "File integrity check failed: Hash mismatch."
            Write-Verbose "Expected: $ExpectedHash"
            Write-Verbose "Actual:   $actualHash"
            return $false
        }
    }
    catch {
        Write-Error "Failed to verify file integrity: $_"
        return $false
    }
}

#endregion


#region Module Initialization

# Export module members
Export-ModuleMember -Function @(
    'Get-FileHashExtended',
    'Get-StringHash',
    'Test-FileIntegrity'
)

#endregion
