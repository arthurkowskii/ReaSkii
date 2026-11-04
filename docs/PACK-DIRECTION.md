# ReaSkii : pack personnel REAPER

## Direction convenue

ReaSkii évolue d'un thème vers un dépôt privé centralisant l'installation REAPER personnalisée d'Arthur : outils MIDI, scripts, configuration sélectionnée, dépendances et installation reproductible. Le thème devient un module facultatif. Arthur est satisfait de Reapertips par défaut ; le développement de nouvelles fonctions ne doit plus dépendre du thème hybride reARK/Reapertips.

Ce document cadre le pack complet, qui n'est pas encore livré. La version publiée reste le thème 0.2.0 et son installateur existant. Un [laboratoire MIDI distinct](MIDI-LAB.md) fournit un premier panneau compagnon testé dans REAPER, sans parité Ableton mesurée. Aucun changement sur le laptop n'est effectué.

## Premier module : MIDI Tools

Objectif : retrouver le workflow du panneau gauche du piano roll d'Ableton, génération comprise, et l'édition d'expression MPE. Fournir une interface commune plutôt qu'une collection d'actions dispersées. Reproduire les usages par une implémentation indépendante, sans promettre un clone exact ni porter des fichiers Max for Live directement.

### Édition de base

Transposition, intervalles, inversion mélodique, adaptation à une gamme, durée, stretch, reverse, legato, humanisation et randomisation contrôlée. Distinguer inversion mélodique et renversement d'accord. Outils de vélocité : rampe, plage, variation et courbe.

### Transformations de référence

La capture et le manuel Live 12 identifient : Arpeggiate, Chop, Connect, Glissando (MPE), LFO (MPE), Ornament, Quantize, Recombine, Span, Strum, Time Warp et Velocity Shaper. Chacun nécessite une spécification de comportement, un inventaire des équivalents REAPER et un choix explicite entre natif, script tiers compatible et implémentation propre.

### Génération de référence

Rhythm, Seed, Shape, Stacks et Euclidean. Ce sont des objectifs fonctionnels, pas une promesse d'algorithmes identiques à ceux d'Ableton. Les extensions Max for Live tierces ne font pas automatiquement partie du périmètre.

### Expression MPE

Cible fonctionnelle : Pitch, Slide, Pressure, Velocity et Release Velocity par note, avec édition de courbes et transformations Glissando/LFO. L'API REAPER expose les notes, canaux, événements CC et événements MIDI bruts ; cela autorise une étude d'implémentation, pas une affirmation de parité avec l'éditeur d'expression d'Ableton.

Point bloquant à prototyper avant l'interface finale : association note/expression via les canaux membres MPE, gestion des notes simultanées, réutilisation de canaux, plage de pitch bend, initialisation/réinitialisation des contrôleurs et préservation des données lors de déplacement, stretch, duplication ou suppression d'une note. Préserver la vélocité de relâchement. Ne pas transformer une note en laissant son expression attachée aux mauvaises positions.

Conserver le piano roll natif de REAPER, sans nouvel éditeur de grille ni dépendance ReaFruit. Une fenêtre compagnon/dockable est la cible initiale du panneau. Une intégration exacte dans le panneau natif de l'éditeur MIDI REAPER n'est pas acquise. Le reverse engineering visé est comportemental : fixtures MIDI identiques, paramètres et version consignés, exports réels de Live et comparaison en temps musical, selon [le protocole de laboratoire](MIDI-LAB.md).

## Architecture et garde-fous proposés

- Conserver le nom et l'historique du dépôt privé ReaSkii ; ne pas supprimer les sources et preuves du thème existant.
- Séparer visuel, outils MIDI, configuration et installation. Les scripts doivent fonctionner avec Reapertips ou un autre thème.
- Garder les réglages de workflow sélectionnés dans Git, pas une copie aveugle du dossier de ressources REAPER. Exclure licences REAPER/plugins, identifiants, caches de scan, données de projets et chemins spécifiques à une machine.
- Installateur idempotent, contrôle des dépendances et de leurs licences, sauvegarde préalable et retour arrière. Ne pas écraser globalement les raccourcis, toolbars ou paramètres existants.
- ReaPack est une option de distribution/mise à jour, pas une dépendance déjà intégrée. Les instruments commerciaux sont des dépendances externes, non des binaires redistribués avec le pack.
- Chaque outil possède une commande indépendante et peut être appelé par le panneau commun. Ne pas dépendre des identifiants d'actions propres à une installation.
- Aperçu calculé depuis un snapshot original, Apply/Cancel, annulation cohérente et graine aléatoire reproductible. Prévenir les transformations cumulatives accidentelles à chaque mouvement de curseur.
- Accessibilité : labels, valeurs et états explicites, jamais une couleur seule.
- Tests dans REAPER portable isolé sur le serveur avant installation volontaire sur le laptop.

## Ordre recommandé

1. Inventaire natif/scripts tiers/licences et spécification de la sélection, du temps et des gammes.
2. Prototype technique MPE sur notes polyphoniques et transformation avec préservation de l'expression.
3. Socle commun et panneau, puis édition de base, Arpeggiate/Strum/Chop et vélocité.
4. Générateurs et autres transformations, par outils vérifiés.
5. Éditeur MPE complet, packaging et mise à jour de l'installation personnelle.

Aucune équivalence complète avec Ableton n'est annoncée avant comparaison fonction par fonction et tests réels.

## Sources consultées

- Ableton Live 12, MIDI Tools : https://www.ableton.com/en/live-manual/12/midi-tools/
- Ableton Live 12, Editing MPE : https://www.ableton.com/en/live-manual/12/editing-mpe/
- REAPER ReaScript API : https://www.reaper.fm/sdk/reascript/reascripthelp.html
- ReaPack : https://reapack.com
- ReaImGui : https://codeberg.org/cfillion/reaimgui
