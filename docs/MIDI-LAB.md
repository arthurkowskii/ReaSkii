# ReaSkii MIDI Tools : laboratoire et protocole Ableton

## Décision

**Contrat prioritaire : [ABLETON-PANEL-CONTRACT.md](ABLETON-PANEL-CONTRACT.md).** Arthur exige la fidélité du comportement et de la logique graphique du panneau Ableton, pas une boîte à outils avec noms similaires. L'interface à boutons/formulaires modaux est un laboratoire technique, pas un résultat conforme. Toute prochaine livraison doit suivre les références visuelles et mesures Live décrites dans ce contrat.

Conserver le piano roll MIDI natif de REAPER. ReaSkii ajoute un panneau d'outils, sans recréer la grille ni dépendre de ReaFruit. Viser le workflow du panneau gauche d'Ableton : édition, transformations, génération et expression MPE.

La première interface est une fenêtre compagnon, avec bouton de docking REAPER. Elle n'est pas une sidebar injectée dans la fenêtre MIDI native. Son placement et son suivi de l'éditeur flottant sous Windows restent à prototyper.

## Ce qui existe dans ce laboratoire

- `scripts/midi/ReaSkii_MIDI_Tools.lua` : action du panneau, utilisant `gfx` intégré à REAPER, sans thème ni extension tiers.
- `scripts/midi/ReaSkii_MIDI_Core.lua` : transformations sur MIDI brut et sessions d'aperçu.
- Transposition, variation de vélocité, randomisation de vélocité à graine déterministe et Strum linéaire sur accords dont les notes commencent exactement ensemble.
- Aperçu depuis le snapshot initial, Apply/Cancel, undo REAPER après Apply et refus d'écraser un MIDI modifié ailleurs.
- Conservation des octets des messages non modifiés, notamment de la vélocité de relâchement. Le Strum ne déplace que les départs, pas les fins.

### Protection des données pendant un aperçu

Un aperçu écrit réellement dans la prise, sans point d'annulation. Pour qu'un plantage ne fasse pas perdre l'original :

1. Avant chaque aperçu, ReaSkii écrit un fichier de récupération dans `ReaSkiiMIDI-recovery/` du dossier de ressources REAPER. Il contient les événements d'origine et les événements d'aperçu.
2. Apply retire ce fichier et crée une seule étape d'annulation nommée. Cancel restaure l'original et retire le fichier.
3. Si le panneau meurt, le fichier reste. À la réouverture, le panneau propose de restaurer.
4. La restauration n'a lieu que si la prise contient encore exactement les octets d'aperçu. Sinon le fichier est conservé et le MIDI édité ailleurs n'est jamais écrasé.
5. Si le MIDI change pendant un aperçu, le panneau abandonne sa session, laisse la modification externe intacte et accepte de repartir.

Échap ne ferme pas le panneau tant qu'un aperçu est en cours, pour éviter de perdre l'aperçu par accident.

### Limites assumées de ce prototype

- Le panneau est une fenêtre compagnon dockable, pas une colonne intégrée à la fenêtre MIDI native.
- Le Strum refuse toute donnée CC/aftertouch/pitch-bend présente dans la prise, même hors de la zone affectée : garde large, mais qui rend l'outil inutilisable sur un MIDI importé contenant de la vélocité ou du volume en CC.
- La transposition refuse la pression polyphonique (0xA0) au lieu de la déplacer, et refuse de faire atterrir une note sélectionnée sur une note non sélectionnée de même hauteur et même canal.
- Les notes non terminées sont ignorées, pas corrigées.
- Aucun test Windows, aucun test avec plusieurs éditeurs MIDI ouverts.

Ce n'est PAS une reproduction complète du panneau Ableton. Générateurs, arpégiateur, tension Strum, tolérance de regroupement des accords et onglet Expression/MPE ne sont pas livrés. Les calculs existants sont indépendants, fondés sur une spécification locale et les comportements documentés, sans mesure de parité avec Live.

## Lancer manuellement dans un REAPER de test

Conserver les deux fichiers Lua côte à côte. Dans la liste d'actions de l'éditeur MIDI, charger `ReaSkii_MIDI_Tools.lua`, sélectionner des notes puis lancer l'action. Les changements restent en aperçu jusqu'à Apply. Cancel ou fermeture du panneau restaure l'original si aucune modification externe n'a eu lieu.

Ne pas éditer les notes ailleurs pendant un aperçu. En cas de conflit, le panneau refuse d'écraser les modifications externes ; leur réconciliation n'est pas automatique. Ne pas utiliser ce laboratoire sur un projet sans sauvegarde.

L'installateur du thème 0.2.0 ne copie pas ces nouveaux scripts. Aucune installation sur le laptop n'est réalisée par ce développement.

## Reverse engineering comportemental

Le manuel est une spécification de référence ; il ne prouve pas les détails internes. Ne pas affirmer une mesure qui n'a pas été faite. Live 12 Suite a été détecté sur le laptop par lecture du dossier d'installation, sans lancement ni modification. L'édition/version exacte et la disponibilité d'une session de comparaison restent à établir.

Pour chaque outil :

1. Créer un MIDI d'entrée déterministe et conserver son fichier original.
2. Noter version Live, outil, paramètres exacts, gamme, grille, swing, sélection et longueur de boucle. Conserver une capture des réglages.
3. Exporter le résultat réel d'Ableton en MIDI dans un dossier d'expérience séparé, sans remplacer un projet utilisateur.
4. Importer la même entrée dans un REAPER portable isolé et exécuter l'équivalent ReaSkii avec les mêmes paramètres.
5. Comparer les événements normalisés en temps musical : hauteurs, début/fin, vélocités d'attaque et de relâchement, canaux et expression. Ne pas comparer directement les octets de deux fichiers MIDI exportés avec des PPQ ou métadonnées différents.
6. Classer la preuve : documenté, observé dans Live, implémenté, testé REAPER, comparé avec Live. Une case non mesurée reste inconnue.
7. Pour les outils aléatoires, séparer la reproductibilité locale d'une égalité avec le générateur pseudo-aléatoire d'Ableton. Vérifier bornes, distribution et contrôles pertinents sans inventer une graine commune.

### Matrice minimale de fixtures à acquérir

- Note seule, accord à départs identiques, accords successifs, notes très légèrement décalées.
- Accords inversés et notes de même hauteur sur canaux différents.
- Limites MIDI 0/127, vélocités 1/127, silences, sélection partielle et absence de sélection.
- Notes muettes, notes répétées, chevauchements et notes traversant les bords de boucle.
- Grille droite/triolet, tempos et changements de tempo, gammes activées/désactivées.
- MPE : deux notes simultanées avec courbes indépendantes, déplacement/stretch/chop, réutilisation de canal, pitch-bend range, reset de contrôleurs et release velocity.

### Premières comparaisons prioritaires

1. Pitch et vélocité : vérifier les bornes et la sélection.
2. Strum avec Tension à zéro : vérifier exactement Low/High, direction, regroupement et interaction avec la grille.
3. Arpeggiate : styles, Rate/Gate, Distance/Steps et gammes.
4. Générateurs, puis transformations et interface MPE par sous-ensembles mesurés.

## Vérification reproductible

Dans le dépôt, avec le binaire externe du REAPER portable isolé :

```sh
xvfb-run -a python3 tests/run_midi_panel.py --reaper /chemin/reaskii-native/REAPER/reaper
xvfb-run -a -s '-screen 0 1400x900x24' python3 tests/run_midi_panel_gui.py --reaper /chemin/reaskii-native/REAPER/reaper
```

Les rapports `qa/midi-panel-native.tsv` et `qa/midi-panel-gui.tsv` contiennent les hashes des entrées de test : cœur, panneau et suites. Résultats actuels : **37 assertions natives** (21 de base, 16 de régression issues de la revue) et **11 assertions d'interface** pilotées par de vrais clics X11. `tests/test_midi_panel.py` refuse un rapport qui ne couvre pas le fichier du panneau ou qui contient un ERROR/FAIL. La capture `qa/midi-panel-native.png` est une capture réelle de l'essai, pas une maquette. Cela ne constitue ni un test Windows ni une comparaison avec Ableton.

## Références

- https://www.ableton.com/en/live-manual/12/midi-tools/
- https://www.ableton.com/en/live-manual/12/editing-mpe/
- https://www.reaper.fm/sdk/reascript/reascripthelp.html
