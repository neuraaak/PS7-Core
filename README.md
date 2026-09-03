# PS7-Core

Bibliothèque de modules PowerShell réutilisables, **PowerShell 7+ uniquement**.

Le nom porte la contrainte : ce module suppose PS7 et Spectre.Console, sans
aucun repli. Un éventuel `PS5-Core` vivrait à côté sans conflit de nom ni de
GUID.

## Contenu

```txt
PS7-Core/                  le module (cible de la jonction d'installation)
├── PS7-Core.psd1/.psm1    méta-module : charge les trois sous-modules
├── PS7-Core.Runtime/      garde d'exécution PS7
├── PS7-Core.UI/           console Spectre.Console
└── PS7-Core.Crypto/       hachage de fichiers et de chaînes
tests/                     suite de tests et test interactif
```

## Prérequis

- PowerShell **7.0+**
- [`PwshSpectreConsole`](https://www.powershellgallery.com/packages/PwshSpectreConsole)
  ≥ 2.3.0 — `Install-Module -Name PwshSpectreConsole -Scope CurrentUser`

`Initialize-EnhancedUI` lève une erreur si le module est absent : pas de mode
dégradé, c'est délibéré.

## Utilisation

Le dossier **parent** de `PS7-Core/` va sur `PSModulePath`, puis un import
unique — `NestedModules` charge les trois sous-modules :

```powershell
$env:PSModulePath += ";<dossier parent de PS7-Core>"
Import-Module PS7-Core
```

Importer `PS7-Core.UI` directement fonctionne aussi, mais l'import unique est
le motif recommandé.

> **Piège.** Après `Import-Module PS7-Core`, les sous-modules ne sont plus des
> modules de premier niveau : `Get-Module PS7-Core.UI` retourne `$null`. Pour
> les atteindre, passer par
> `(Get-Module PS7-Core).NestedModules | Where-Object Name -eq 'PS7-Core.UI'`.

Dans un script, épingler la version :

```powershell
#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'PS7-Core'; ModuleVersion = '1.1.0' }
```

## Installation

PS7-Core ne s'installe pas lui-même : le bootstrap ne peut pas vivre dans le
dépôt qu'il doit cloner. **C'est au projet consommateur** de porter son script
d'installation — typiquement un clone hors dossier synchronisé, puis une
jonction de répertoire vers `PS7-Core/`, posée à l'emplacement du script.

## Fonctions exportées

### PS7-Core.Runtime

| Fonction | Rôle |
| --- | --- |
| `Assert-PowerShell7` | Lève une erreur actionnable si PS < 7.0 (ou `-MinimumVersion`) |

### PS7-Core.UI

| Fonction | Rôle |
| --- | --- |
| `Initialize-EnhancedUI` | Initialise la console Spectre ; erreur si absente |
| `Write-Header` | En-tête de section |
| `Write-StatusMessage` | Message typé (`Info`, `Success`, `Warning`, `Error`) |
| `Write-ProgressBar` | Barre de progression |
| `Write-Summary` | Résumé de fin d'exécution |
| `Read-Selection` | Invite à cocher générique (Spectre), repli texte si l'appel échoue |
| `Read-FolderSelection` | Racine + sous-dossiers directs, exclusion par nom, sélection optionnelle |
| `Start-ProgressScope` | Bascule `Write-ProgressBar`/`Write-StatusMessage` en rendu Spectre live |

`Start-ProgressScope` remplace `Write-Progress` natif, qui corrompt
visuellement l'affichage sous forte charge d'impression.

> **Piège de scope.** Le scriptblock passé à `Start-ProgressScope` s'exécute
> dans un scope enfant. Toute variable réaffectée dedans (`=`, `+=`, `++`) crée
> une copie locale perdue à la sortie. Muter un membre d'objet
> (`$table[$k] = $v`, `$liste.Add(...)`) fonctionne. Pour accumuler, utiliser
> `[System.Collections.Generic.List[object]]` plutôt qu'un tableau et `+=`.
> Les invites interactives doivent rester **hors** de tout scope : Spectre ne
> sait pas imbriquer deux régions live, et l'imbrication de scopes lève une
> erreur.

### PS7-Core.Crypto

| Fonction | Rôle |
| --- | --- |
| `Get-FileHashExtended` | Hash d'un fichier (SHA256 / SHA1 / MD5) |
| `Get-StringHash` | Hash d'une chaîne |
| `Test-FileIntegrity` | Compare un fichier à un hash attendu |

## Tests

```powershell
pwsh -NoProfile -File tests/Test-PS7Core.ps1
```

21 cas automatisés. `tests/Test-ReadFolderSelection.ps1` est un test **manuel
interactif** : il construit une arborescence jetable et lance la vraie invite
Spectre, nécessaire parce qu'une entrée redirigée fait toujours tomber
`Read-SpectreMultiSelection` en mode non interactif.

## Ajouter une fonction

Mettre à jour `FunctionsToExport` du `.psd1` **du sous-module et de la
racine** — sinon la fonction n'est pas visible à l'import.

## Licence

MIT
