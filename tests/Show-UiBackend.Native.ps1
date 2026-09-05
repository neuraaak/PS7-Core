<#
.SYNOPSIS
    Controle du backend UI Native : robustesse + rendu visuel.

.DESCRIPTION
    Deux volets, definis dans UiBackendChecks.ps1 (partage avec l'autre
    lanceur, pour que les deux backends soient mesures exactement pareil) :

      - Robustesse : assertions automatiques sur les arguments invalides, les
        valeurs limites, les mauvais types, l'injection de markup et la parite
        de comportement entre backends. Sortie 1 si un cas echoue.
      - Rendu : sortie a inspecter a l'oeil. Un shell redirige ne rend ni
        Write-Progress ni Spectre, donc ce volet n'a de sens que dans un VRAI
        terminal.

    N'a besoin de rien d'autre que PowerShell 7. Force le backend natif meme
    sur une machine ou Spectre est installe : c'est ainsi qu'on couvre le chemin
    utilise sur un hote contraint.

.PARAMETER SkipVisual
    N'execute que les assertions. Utilisable depuis un shell redirige ou en CI.

.PARAMETER OnlyVisual
    N'execute que la demonstration visuelle.

.EXAMPLE
    .\Show-UiBackend.Native.ps1
    Assertions puis rendu.

.EXAMPLE
    .\Show-UiBackend.Native.ps1 -SkipVisual
    Assertions seules, exploitable sans terminal.
#>

#Requires -Version 7.0

[CmdletBinding()]
param (
    [switch]$SkipVisual,
    [switch]$OnlyVisual,

    # Valeurs extremes (message de 4000 caracteres, titre de 400) : couvrantes
    # mais bruyantes, le backend Spectre ne pouvant pas etre reduit au silence.
    [switch]$Thorough
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'UiBackendChecks.ps1')

exit (Invoke-UiBackendCheck -Backend Native -SkipVisual:$SkipVisual -OnlyVisual:$OnlyVisual -Thorough:$Thorough)
