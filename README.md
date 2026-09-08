# PS7-Core

Bibliothèque de modules PowerShell réutilisables, **PowerShell 7+ uniquement**.

Le nom porte la contrainte : ce module suppose PS7, et rien d'autre —
Spectre.Console est utilisé s'il est là, sans être requis. Un éventuel
`PS5-Core` vivrait à côté sans conflit de nom ni de GUID.

## Contenu

```txt
PS7-Core/                  le module (cible de la jonction d'installation)
├── PS7-Core.psd1/.psm1    méta-module : charge les trois sous-modules
├── PS7-Core.Runtime/      garde d'exécution PS7
├── PS7-Core.UI/           console, deux backends (Spectre / natif)
└── PS7-Core.Crypto/       hachage de fichiers et de chaînes
tests/                     suite de tests et test interactif
```

## Prérequis

- PowerShell **7.0+** — seul prérequis strict.
- [`PwshSpectreConsole`](https://www.powershellgallery.com/packages/PwshSpectreConsole)
  ≥ 2.3.0 — *optionnel* : `Install-Module -Name PwshSpectreConsole -Scope CurrentUser`

## Les deux backends d'affichage

`PS7-Core.UI` a deux implémentations interchangeables :

| Backend   | Base               | Usage                         |
| --------- | ------------------ | ----------------------------- |
| `Spectre` | PwshSpectreConsole | rendu riche, progression live |
| `Native`  | PowerShell 7 pur   | aucune dépendance externe     |

Le backend est résolu **une fois**, par `Initialize-EnhancedUI`, jamais par
appel : le choix dépend de l'environnement, pas du site d'appel. Les fonctions
publiques n'exposent donc aucun paramètre de backend, et **le code appelant est
identique dans les deux modes**.

```powershell
Initialize-EnhancedUI                    # Auto : Spectre si dispo, natif sinon
Initialize-EnhancedUI -Backend Native    # force le natif (tests, hôte contraint)
Initialize-EnhancedUI -Backend Spectre   # erreur franche si Spectre manque
```

En `Auto`, la bascule vers le natif affiche **une ligne, une seule fois** : la
dégradation n'est jamais silencieuse. Le backend actif se lit par
`(Get-UIContext).Backend`.

> **`Get-UIContext` est le seul accès.** L'état vit dans une variable de
> module qui n'est pas exportée : `Export-ModuleMember -Variable` ne traverse
> pas la frontière de sous-module imbriqué, donc `$UIContext` n'existerait côté
> appelant qu'en import direct de `PS7-Core.UI`, jamais après
> `Import-Module PS7-Core`. Plutôt qu'un accès qui marche d'un côté et échoue en
> silence de l'autre, il n'y en a qu'un.

**Les barres ne se comportent pas pareil en fin de parcours** : Spectre laisse
la sienne affichée à 100 % avec sa description, `Write-Progress` efface sa
région et ne laisse rien. Aucun des deux n'est un défaut — mais un script dont
la sortie est relue après coup n'aura de trace de progression qu'en Spectre.

Le rendu natif est délibérément **plus pauvre**, pas équivalent : viser
l'équivalence visuelle mène aux impasses déjà rencontrées (barre inline maison
dont les lignes de statut se collent à la progression). La progression native
utilise `Write-Progress` en vue `Minimal`, validé sous forte charge
d'impression ; le filet de `Write-Header` retombe sur `-` quand l'encodage de
sortie n'est pas UTF-8.

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

Dans un script, épingler la version **après** l'import :

```powershell
#Requires -Version 7.0

$env:PSModulePath += ";<dossier parent de PS7-Core>"
try { Import-Module PS7-Core -ErrorAction Stop }
catch { throw "PS7-Core introuvable. Lancez le script d'installation du projet." }

$ps7Core = Get-Module PS7-Core
if ($ps7Core.Version -lt [version]'1.2.0') {
    throw "PS7-Core $($ps7Core.Version) est trop ancien, 1.2.0 minimum requis."
}
```

> **N'utilisez pas `#Requires -Modules` ici.** La directive est évaluée *avant*
> le corps du script, donc avant que celui-ci ait complété `PSModulePath` : avec
> une liaison par jonction elle échoue systématiquement. Le contrôle de version
> se fait donc après l'import, et **hors du `try`** — sinon une version
> insuffisante serait rapportée comme un module introuvable.

## Installation

PS7-Core ne s'installe pas lui-même : le bootstrap ne peut pas vivre dans le
dépôt qu'il doit cloner. **C'est au projet consommateur** de porter son script
d'installation — typiquement un clone hors dossier synchronisé, puis une
jonction de répertoire vers `PS7-Core/`, posée à l'emplacement du script.

## Fonctions exportées

### PS7-Core.Runtime

| Fonction             | Rôle                                                           |
| -------------------- | -------------------------------------------------------------- |
| `Assert-PowerShell7` | Lève une erreur actionnable si PS < 7.0 (ou `-MinimumVersion`) |

### PS7-Core.UI

| Fonction                | Rôle                                                                     |
| ----------------------- | ------------------------------------------------------------------------ |
| `Initialize-EnhancedUI` | Initialise la console et résout le backend (`Auto`/`Spectre`/`Native`)  |
| `Write-Header`          | En-tête de section                                                       |
| `Get-UIContext`         | Backend actif et état d'initialisation                                  |
| `Write-StatusMessage`   | Message typé (`Info`, `Success`, `Warning`, `Error`, `Skipped`, `Debug`) |
| `Write-ProgressBar`     | Barre de progression                                                     |
| `Write-Summary`         | Résumé de fin d'exécution                                                |
| `Read-Selection`        | Invite à cocher générique (Spectre), repli texte si l'appel échoue       |
| `Read-FolderSelection`  | Racine + sous-dossiers directs, exclusion par nom, sélection optionnelle |
| `Start-ProgressScope`   | Bascule `Write-ProgressBar`/`Write-StatusMessage` en rendu Spectre live |

`Start-ProgressScope` ouvre une région live Spectre. Avec le backend natif il
n'y a pas de région à ouvrir — `Write-ProgressBar` utilise directement
`Write-Progress` — mais **c'est toujours un vrai scope**, invoqué via `&` comme
son homologue Spectre : le piège de portée ci-dessous se comporte donc à
l'identique dans les deux backends, et un script validé sur l'un se comporte
pareil sur l'autre.

> **Piège de scope.** Le scriptblock passé à `Start-ProgressScope` s'exécute
> dans un scope enfant. Toute variable réaffectée dedans (`=`, `+=`, `++`) crée
> une copie locale perdue à la sortie. Muter un membre d'objet
> (`$table[$k] = $v`, `$liste.Add(...)`) fonctionne. Pour accumuler, utiliser
> `[System.Collections.Generic.List[object]]` plutôt qu'un tableau et `+=`.
> Les invites interactives doivent rester **hors** de tout scope : Spectre ne
> sait pas imbriquer deux régions live, et l'imbrication de scopes lève une
> erreur.

### PS7-Core.Crypto

| Fonction               | Rôle                                    |
| ---------------------- | --------------------------------------- |
| `Get-FileHashExtended` | Hash d'un fichier (SHA256 / SHA1 / MD5) |
| `Get-StringHash`       | Hash d'une chaîne                       |
| `Test-FileIntegrity`   | Compare un fichier à un hash attendu    |

## Tests

```powershell
pwsh -NoProfile -File tests/Test-PS7Core.ps1
```

```powershell
pwsh -NoProfile -File tests/Test-PS7Core.ps1 -Backend Native
```

### Contrôle d'un backend : robustesse + rendu

```powershell
pwsh -NoProfile -File tests/Show-UiBackend.Native.ps1
pwsh -NoProfile -File tests/Show-UiBackend.Spectre.ps1
```

Deux volets, définis dans `tests/UiBackendChecks.ps1` — partagé par les deux
lanceurs, pour que les backends soient mesurés exactement pareil et ne dérivent
pas l'un de l'autre :

- **Robustesse** — 27 assertions : arguments invalides, valeurs limites
  (`Total = 0`, `Current` négatif ou hors borne, titre plus large que la
  console), mauvais types, injection de markup, parité du piège de portée entre
  backends. Sortie 1 si un cas échoue. `-SkipVisual` les exécute seules, sans
  terminal. `-Thorough` pousse les entrées longues à l'extrême (message de
  4000 caractères, titre de 400) : couvrant mais bruyant, car `Write-SpectreHost`
  écrit droit sur la console et échappe à toute redirection de flux — le moteur
  de rendu n'est délibérément pas neutralisé, vérifier qu'il encaisse une entrée
  longue faisant partie de l'intérêt du test.
- **Rendu** — sortie à inspecter à l'œil : les six types de message, une
  progression seule, une progression avec messages entrelacés (le cas qui
  corrompait l'affichage), deux barres simultanées. `-OnlyVisual` s'y limite.

Un shell redirigé ne rend ni `Write-Progress` ni Spectre : le volet visuel n'a
de sens que dans un **vrai terminal**.

### Suite principale

La suite doit passer **dans les deux backends**. `-Backend Native` force le
chemin sans dépendance même sur une machine qui a Spectre : c'est la seule
façon de le couvrir sans machine dédiée, et sans cette passe il pourrirait en
silence jusqu'au jour où il devient le seul disponible. Les cas qui inspectent
des internes propres à un backend sont ignorés proprement dans l'autre passe. `tests/Test-ReadFolderSelection.ps1` est un test **manuel
interactif** : il construit une arborescence jetable et lance la vraie invite
Spectre, nécessaire parce qu'une entrée redirigée fait toujours tomber
`Read-SpectreMultiSelection` en mode non interactif.

## Ajouter une fonction

Mettre à jour `FunctionsToExport` du `.psd1` **du sous-module et de la
racine** — sinon la fonction n'est pas visible à l'import.

## Licence

MIT
