# ReaSkii

**Direction du projet : un pack personnel REAPER, indépendant du thème.** Le dépôt a vocation à centraliser outils MIDI, scripts, configuration sélectionnée et installation reproductible. Reapertips par défaut convient à Arthur ; le thème hybride reste conservé comme module historique/facultatif. Le premier périmètre demandé est le panneau d'outils MIDI inspiré d'Ableton : édition, transformations, génération et expression MPE.

Voir [le cadrage du pack](docs/PACK-DIRECTION.md) pour les fonctionnalités visées, les limites et les garde-fous. **Le pack MIDI complet n'est pas encore implémenté.** Un [premier laboratoire MIDI](docs/MIDI-LAB.md) ajoute un panneau compagnon au piano roll natif : transposition, vélocité et Strum linéaire avec aperçu réversible. Il n'est pas encore comparé aux sorties MIDI d'Ableton.

La livraison **0.3.0** contient le thème 0.2.0 **et** les outils : panneau MIDI, device rack, script d'enregistrement des actions. L'installeur copie tout ; un script dédié déclare les actions, une fois par machine.

## Thème 0.2.0 existant

**Fonctionnement et réglages Reapertips, graphismes reARK X.** Exception voulue : la présentation reARK des plugins dans la colonne droite du TCP est conservée.

Cette version remplace le moteur reARK partiellement modifié des versions 0.1.x par le moteur WALTER de **Reapertips v1.95a Dark**. Les options de placement, masquage A/B/C, listes, enveloppes, mixer, transport et indentation viennent désormais de cette base. Les 2 892 fichiers d'art d'origine, couleurs et définitions de polices reARK sont conservés à l'identique. Aucune image ni police Reapertips n'est incluse.

## Réglages par défaut

- Réglages Reapertips, sauf **Track name takes the whole row** activé à la demande d'Arthur.
- **Smart folder indent** activé ; quatre « ...but keep » désactivés comme dans Reapertips.
- **Keep reARK FX presentation on the TCP right** activé : liste combinée native, police/marges reARK, largeur 130 px, deux colonnes maximum et rangées de 16 px à 100 %. Largeur et hauteur réglables par paliers, comme dans reARK.
- Désactiver cette dernière option rend la gestion des listes au moteur Reapertips.
- Le skin reARK remplace volontairement les panneaux peints et les choix de polices de Reapertips. Les contrôles de teinte de ces panneaux ne reproduisent donc pas le rendu Reapertips. Les variantes purement graphiques sans images reARK correspondantes (Solid, fader White, transport Classic) ne sont pas proposées.
- Pour les fonctions absentes du graphisme reARK d'origine, de petits sprites originaux **P/p** (épinglé/non épinglé) et **C** (comping) sont générés, en trois états et aux trois échelles. Les connecteurs de dossiers réutilisent les images reARK, sans modifier les originaux.

Le nom pleine ligne occupe la largeur disponible hors dossiers, mètres et colonne FX. Les « keep » choisissent le placement, pas la visibilité : les masques du layout **réellement utilisé**, notamment **A**, restent applicables. Pour les deux boutons rotatifs près du nom, activer **...but keep volume** et **...but keep pan**. L'InfoBlock doit être activé pour être conservé.

## Outils

Deux actions, installées par le paquet et déclarées par `ReaSkii_RegisterTools.lua` :

- **ReaSkii MIDI Panel** (section MIDI Editor) : panneau compagnon du piano roll natif, qui reste inchangé. Transposition, vélocité et Strum linéaire, avec aperçu réversible avant Apply.
- **ReaSkii Device Rack** (section Main) : fenêtre compagnon du rack de devices, adossée à la chaîne FX native de la piste sélectionnée.

Le prototype de laboratoire `scripts/midi/ReaSkii_MIDI_Tools.lua` est installé mais volontairement non déclaré. Le charger à la main depuis la liste d'actions si besoin.

## Installer ou mettre à jour sous Windows

**Mise à jour en une commande**, REAPER fermé :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/arthurkowskii/ReaSkii/main/Get-ReaSkii.ps1 | iex"
```

La commande prend la dernière release publiée, vérifie le manifeste SHA-256 et installe avec `-Update`. Le numéro de version s'affiche avant l'installation. `Get-ReaSkii.ps1 -Package 'D:\ReaSkii.zip'` fonctionne hors ligne, depuis une clé USB.

Installation manuelle :

1. **Fermer REAPER**, puis décompresser `ReaSkii-v0.3.0.zip`.
2. Dans ce dossier, lancer :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ReaSkii.ps1 -Update
```

Pour REAPER portable, ajouter `-ResourcePath 'chemin\vers\les\ressources\REAPER'`. Sans `-Update`, l'installeur refuse de remplacer une installation différente.

3. Relancer REAPER, sélectionner **Options > Themes > ReaSkii**, puis ouvrir **Options > Themes > Theme adjuster** (action 42234).
4. Déclarer les actions une fois par machine : **Actions > Show action list > Load ReaScript**, choisir `Scripts\ReaSkii\ReaSkii_RegisterTools.lua`, puis **Run**. Le script enregistre `ReaSkii MIDI Panel` (section MIDI Editor) et `ReaSkii Device Rack` (section Main) et affiche leurs command IDs. Les chemins ne changent pas d'une version à l'autre, donc l'étape n'est pas à refaire après une mise à jour.

**Important : ouvrir l'ajusteur fait partie de la mise à jour du thème.** À sa première ouverture avec le moteur 0.2, il sauvegarde les valeurs mémorisées et applique les nouveaux défauts, au lieu de conserver les anciens masquages reARK. Cela ne se répète pas à chaque ouverture : les modifications personnelles suivantes sont conservées.

L'installeur prévalide tous les fichiers, sauvegarde les anciens fichiers ReaSkii et `reaper-themeconfig.ini`, vérifie les copies par SHA-256 et tente un retour arrière en cas d'échec. Les sauvegardes sont dans `ReaSkii-backups/` du dossier de ressources. Il ne ferme pas REAPER, n'active pas de thème et ne modifie ni projet ni thème reARK/Reapertips original.

Fichiers installés :

- `ColorThemes/ReaSkii.ReaperThemeZip`
- `Scripts/Cockos/ReaSkii_Adjuster.lua`
- `Scripts/Cockos/ReaSkii_Defaults.lua`
- `Scripts/Cockos/ReaSkii_ApplyDefaults.lua`
- `Scripts/ReaSkii/ReaSkii_RegisterTools.lua`
- `Scripts/ReaSkii/midi/*.lua` (panneau MIDI et ses modules)
- `Scripts/ReaSkii/device/*.lua` (device rack et ses modules)

Le dossier `Cockos` est imposé par REAPER pour `adjuster_script` ; ces scripts ne sont pas des produits Cockos. En installation manuelle, copier **tout l'arbre**, pas seulement le thème, puis suivre les étapes 3 et 4.

## Ajusteur et sauvegardes

- **First row** : options usuelles et exception FX reARK.
- **TCP / Mixer / Other / All** : paramètres complets du moteur, recherche, défilement et édition. Les masques TCP se règlent par menu explicite plutôt que par bits à deviner.
- **Apply Reapertips / ReaSkii defaults** : remise à zéro volontaire, précédée d'une sauvegarde.
- `ReaSkii_ApplyDefaults.lua` peut aussi être chargé dans Actions et exécuté une fois avec le thème 0.2 actif.
- Chaque remise à zéro crée un script `ReaSkii-backups/Restore-before-defaults-*.lua`. Le charger dans Actions avec ReaSkii 0.2 actif restaure les valeurs précédentes.
- Pour revenir à 0.1.x, fermer REAPER, restaurer les fichiers de la sauvegarde d'installation et, si nécessaire, son `reaper-themeconfig.ini`. Ce dernier contient les réglages de tous les thèmes : le restaurer annule aussi les modifications de thèmes effectuées depuis cette sauvegarde.

## Vérification et développement

```sh
python3 build.py
python3 -m unittest discover -s tests -v
```

Le build déterministe produit le thème et le paquet autonome avec manifeste SHA-256. `upstream/rtconfig.txt` conserve reARK ; `upstream/reapertips/rtconfig.txt` conserve le moteur de référence. `src/engine.py` applique les changements explicitement bornés ; `src/reark-skin.walter` contient le skin et l'exception FX. `src/reaskii.walter` et `tests/native.lua` restent des archives de 0.1, non utilisés par le nouveau build/harness.

Les tests natifs utilisent REAPER 7.84 Linux/Xvfb dans une installation portable isolée, jamais la session quotidienne du laptop. Le runner `tests/run_native.py` utilise `tests/native_v02.lua` et écrit `qa/v02-native-*.tsv`. Il vérifie les valeurs par défaut, migration/restauration, A/B/C à 100/150/200 %, contrôles compacts, colonne FX et visibilité des labels MCP. Les contrôles essentiels sont mesurés aux hauteurs réelles de 50/58/61/65 px, pas seulement déclarés visibles dans une capture. La validation MCP ne constitue pas une couverture complète de ses contrôles ; la géométrie EnvCP n'est pas entièrement automatisée.

Les captures contiennent de vrais plugins JS chargés dans REAPER. Le test d'ajusteur utilise l'action standard, un vrai clic et un second processus pour vérifier la persistance. Voir `qa/VERIFICATION-v02.md` pour les résultats et limites. Ce n'est pas une validation runtime Windows.

## Crédits et licence

reARK X : **ARKADATA / Pierre Daunis**. Moteur Reapertips : **Alejandro Hernandez et FeedTheCat / Ilias-Timon Poulakis**. REAPER/WALTER : **Cockos**.

Dépôt public depuis le 4 novembre 2026, personnalisation personnelle, non monétisée. reARK X est sous CC BY-NC-SA 4.0 : réutilisation non commerciale, attribution, partage à l'identique ; son fichier de licence est conservé. Le moteur Reapertips provient d'un thème vendu séparément, ses droits ne sont pas assimilés à cette licence. Les scripts sous `scripts/` sont le code propre de ReaSkii. Voir `THIRD_PARTY_NOTICES.md`.
