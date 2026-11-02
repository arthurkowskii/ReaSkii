# ReaSkii

Variante personnelle de **reARK X**, avec son apparence d'origine et trois ajouts inspirés du thème Reapertips :

- **Track name takes the whole row**, activé par défaut : le nom utilise la place disponible sur la première ligne du TCP ; les boutons d'armement et de monitoring restent accessibles.
- Quatre options indépendantes **...but keep volume / pan / infoblock / routing button** pour garder ces éléments sur la première ligne. Elles sont désactivées par défaut, comme dans Reapertips.
- **Smart folder indent**, activé par défaut : les niveaux de dossiers profonds prennent progressivement moins de place, dans le TCP, les enveloppes et le mixer.

L'InfoBlock natif est également disponible. Activer **Use InfoBlock** avant d'utiliser **...but keep infoblock**.

Les layouts A/B/C et leurs variantes 100/150/200 % sont conservés. Les images, couleurs et polices viennent de reARK X, sans import d'images de Reapertips.

## Installation Windows

Décompresser le paquet de livraison, puis lancer dans PowerShell :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ReaSkii.ps1
```

Pour une installation portable, ajouter `-ResourcePath 'chemin\vers\les\ressources\REAPER'`.

L'installation copie uniquement :

- `ColorThemes/ReaSkii.ReaperThemeZip`
- `Scripts/Cockos/ReaSkii_Adjuster.lua`

Le dossier `Cockos` est imposé par la résolution de `adjuster_script` de REAPER ; le script ReaSkii n'est pas un produit de Cockos. L'installeur refuse d'écraser une version différente. Il ne change pas le thème actif, ne ferme pas REAPER et ne modifie aucun projet ni fichier de réglages.

Choisir ensuite **Options > Themes > ReaSkii**. Les nouvelles options sont dans **Options > Themes > Theme adjuster** (action 42234). Le bouton **Original reARK X / V6 controls...** ouvre l'ajusteur standard pour les autres réglages.

Installation manuelle : copier les deux fichiers aux emplacements ci-dessus. Pour revenir en arrière, sélectionner le thème reARK X original. Aucun redémarrage n'est normalement nécessaire pour changer de thème.

### Mise à jour 0.1.0 vers 0.1.1

L'ajusteur est inchangé. Sauvegarder le précédent `ColorThemes/ReaSkii.ReaperThemeZip` hors du dossier ColorThemes, puis le remplacer par celui du nouveau paquet. Recharger ReaSkii en sélectionnant temporairement reARK X puis ReaSkii. Les paramètres existants restent conservés. L'installeur de première installation refuse volontairement d'écraser l'ancienne version.

Pour la disposition de la capture Reapertips avec les deux boutons rotatifs à droite du nom, activer **...but keep volume** et **...but keep pan**. La visibilité générale des contrôles reste réglée par l'ajusteur reARK X/V6 : les « keep » changent la rangée, pas les règles de masquage.

## Comportements à connaître

- Depuis 0.1.1, les marges verticales se réduisent en mode pleine ligne pour préserver deux rangées dans les pistes de 50 à 60 pixels à 100 % (hauteurs proportionnelles en HiDPI). À hauteur minimale, une seule rangée reste physiquement possible et les contrôles non conservés sont masqués.
- Un panneau extrêmement étroit, notamment avec les très grands mètres du layout C à 200 %, conserve le repli vertical de reARK X. « Pleine ligne » signifie la largeur disponible pour les contrôles, pas la zone réservée aux mètres, aux dossiers ou à une colonne FX latérale.
- Désactiver la nouvelle option rétablit le flux de placement de reARK X. Certains anciens cas de nom masqué dans des panneaux étroits restent caractérisés dans les tests ; ils ne sont pas introduits par le mode pleine ligne.
- Le réglage d'indentation de base de reARK X reste appliqué. Un indent de base nul annule l'indentation, même avec Smart folder indent activé.

## Développement

Python 3, bibliothèque standard uniquement pour construire et lancer les tests de contrat :

```sh
python3 build.py
python3 -m unittest discover -s tests -v
```

Le build produit `dist/ReaSkii.ReaperThemeZip` et le paquet autonome `dist/ReaSkii-v0.1.1.zip` (thème, ajusteur, installeur, documentation et manifeste SHA-256).

Le ZIP de thème est reproductible. `upstream/` conserve les règles et couleurs originales ; `src/reaskii.walter` contient les ajouts ; `build.py` applique les adaptations ciblées aux trois panneaux. Les assets sont conservés sous `theme/ReaSkii/` et vérifiés par hash.

Les tests natifs nécessitent une installation REAPER de test externe au dépôt, sous un chemin contenant `reaskii-native`, ainsi que Xvfb. Les captures et tests de souris utilisent Pillow et libXtst. Aucun exécutable ni fichier de licence REAPER n'est fourni.

```sh
xvfb-run -a -s '-screen 0 1800x1200x24' python3 tests/run_native.py --reaper-dir /chemin/reaskii-native/REAPER --width 960
xvfb-run -a -s '-screen 0 1800x1200x24' python3 tests/run_native.py --reaper-dir /chemin/reaskii-native/REAPER --width 640
xvfb-run -a -s '-screen 0 1800x1200x24' python3 tests/run_native.py --reaper-dir /chemin/reaskii-native/REAPER --width 540
xvfb-run -a -s '-screen 0 1800x1200x24' python3 tests/run_native.py --reaper-dir /chemin/reaskii-native/REAPER --width 320
```

Les preuves de rendu et rapports natifs sont dans `qa/`. Ces tests vérifient le moteur WALTER de REAPER 7.84 sous Linux, pas une session Windows sur le laptop.

## Crédits et redistribution

- **reARK X** : ARKADATA / Pierre Daunis, thème de base et assets.
- **Reapertips Theme** : Alejandro Hernandez et FeedTheCat / Ilias-Timon Poulakis, référence des comportements de première ligne et d'indentation.
- **REAPER / WALTER** : Cockos.

Dépôt **privé**. reARK X est fourni sous CC BY-NC-SA 4.0, dont le fichier original est préservé dans le thème. ReaSkii est un fork non monétisé avec attribution. Cette livraison personnelle ne publie pas le projet et ne prétend pas établir les droits de tous les éléments tiers. Voir `THIRD_PARTY_NOTICES.md`.
