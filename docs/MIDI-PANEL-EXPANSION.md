# ReaSkii companion panel — expansion partielle

Le contrat `ABLETON-PANEL-CONTRACT.md` reste contraignant. Cette livraison élargit le même panneau inline; elle ne termine pas la parité Live. Le piano roll REAPER reste natif. Aucun moteur partagé, Tools, Expression ou adaptateur MPE n'a été modifié. Pas d'installation/déploiement/commit.

## Audit ergonomie: glisser vs taper, comparaison Ableton

Vérifié en REAPER/Xvfb (`tests/run_midi_expansion_polish_probe.py`, rapport `qa/midi-expansion-polish-probe.tsv`): les champs numériques acceptent un glissé vertical (1 pas/pixel, Shift = 0.1 pas avant arrondi), la molette (1 pas/cran), un clic puis saisie clavier/Entrée, et un double-clic remet le défaut. Le glissé met à jour le MIDI réel et Cancel restaure.

Défaut trouvé et corrigé: sur un paramètre entier, dix crans de molette avec Shift étaient arrondis à zéro à chaque cran. Les sous-pas s'accumulent désormais; vérifié nativement (quatre à cinq pas après dix crans). Tests Lua DONE11 et suite native DONE69 après correction. Une première exécution native a échoué sur Ornament (course de rafraîchissement du harness), repassée verte au rerun; à stabiliser.

Manuel Live 12, section 42.6: flèches haut/bas, Shift pour réglage fin, Shift pendant le glissé pour résolution plus fine, Delete pour défaut, saisie directe 0-9, Entrée/Esc. Référence visuelle `MIDIToolSeedL12.png`: trois sliders à deux poignées Pitch/Duration/Velocity plus Voices et Density; `MIDIToolShapeL12.png`: courbe dessinée et quatre rotatifs Rate/Tie/Density/Jitter; `MIDIToolRhythmL12.png`: rotatifs Steps/Pattern/Density, Step Duration, Split/Shift/Accent. Ces éléments graphiques ne sont pas encore présents.

Opportunités classées: (1) sliders à poignées et rotatifs des générateurs, (2) flèches clavier et touche Delete dans les champs, (3) unités musicales lisibles (1/64, 1/8) à la place de 0.50, (4) Reset grisé à l'état défaut comme le manuel, (5) affordance de glissé visible (les boîtes ressemblent à des champs texte), (6) valeurs par outil au lieu du partage actuel. Aucune n'est déclarée faite sans test.

## Priorité confirmée par Arthur

Le 1:1 des sections Transform et Generate est prioritaire: inventaire complet, paramètres/plages/défauts, contrôles graphiques et gestes, previews et comportement MIDI. Les variantes partielles actuelles ne constituent pas le résultat final. Clip/Launch, habillage général et intégration de fenêtre passent après cette fidélité, sans affaiblir la sûreté ni remplacer le piano roll natif. La fidélité visuelle et fonctionnelle doit être vérifiée séparément; les différences non mesurées avec Live restent explicitement ouvertes.

## Point de reprise: Quantize, contrôles de référence

Ce lot remplace le sous-panneau Quantize générique par le groupement vu dans l'image officielle `MIDIToolQuantizeL12.png`: Grid, boutons 1/4 / 1/8 / 1/16 / 1/32 en deux colonnes, case Triplets (inactive avec Grid), Start et End indépendants, Amount rotatif avec valeur numérique. Les contrôles restent inline et dessinés en primitives originales.

Le moteur privé traite désormais End seul et Start+End, avec Amount proportionnel. Start seul conserve la durée; End seul conserve le départ; les deux activés quantifient séparément les bornes. Désactiver les deux ou Amount=0 n'altère pas les notes. Les durées qui s'effondrent, les collisions et les données d'expression ambiguës sont refusées. Grilles/toggles Quantize sont séparés de la grille des autres outils.

Preuve: test `midi_expansion_quantize.lua` observé rouge avant implémentation puis DONE8; intégration DONE10 et safety DONE7 restent verts. `run_midi_expansion_quantize_gui.py` a réellement passé DONE69 dans REAPER/Xvfb, comprenant les 61 scénarios de régression adaptés au nouveau choix de grille et les nouveaux gestes/cas Quantize. Rapport hashé et captures nouveaux préfixes `qa/midi-expansion-quantize-*`; les anciens rapports sont conservés. Capture `midi-expansion-quantize-panel.png` vue et comparée à l'image officielle.

Ceci établit le fonctionnement et le groupement de contrôles, pas une égalité mesurée avec Live: sensibilité des gestes, arrondi/midpoint, sélection sans notes explicites et détails de thème restent à comparer. Tie-down et comportement Start seul restent des politiques locales non validées par exports Live. Le problème de binaire absent décrit plus bas appartient au lot initial et est maintenant levé; les restrictions des autres outils restent ouvertes.

## Fonctionnalités raccordées

- Pitch & Time: affichage MIDI C-1 conventionnel, transposition relative, duplication Add Interval (demi-tons, refus de collision), longueur selon grille Native/1/4/1/8/1/16/1/32 et triplets, Humanize déterministe des positions avec durée préservée, Apply Stretch explicite même Auto OFF. Fit Scale, inversion, Reverse, Legato et Strum existants conservés.
- Un seul chooser Transform, ordre de référence conservé: Arpeggiate (trois styles seulement), Chop (subdivision régulière seulement), Connect, Ornament, Quantize (départs/durée conservée), Recombine, Span, Strum, Velocity Shaper. Glissando/LFO MPE et Time Warp restent désactivés.
- Generate: Rhythm, Euclidean, Seed, Shape et Stacks utilisent l'adaptateur privé configuré avec Generators. Auto, Generate, Reset et Cancel passent par les mêmes snapshots/journaux. ADD par défaut; REPLACE nécessite armement explicite visible, supprime uniquement les notes débutant dans la plage. Aucun effacement si le résultat généré est vide. Collisions/expression/attachements refusés.
- Clip: vrai nom de take (nom de clip REAPER), position/durée en secondes, offset, playrate et état B_LOOPSRC. Bouton de boucle source avec undo et lecture de vérification, limité à cet item. Pas de faux lancement Session.

## Implémentations indépendantes / restrictions

Sémantiques basées sur manuel Live 12, chapitres 11.1 et 11.2, sans algorithme propriétaire ni export Live mesuré:

- Connect: séquence monophonique non chevauchante requise. Remplissage par slots entiers dans les gaps, probabilité locale de densité/tie et décalage pitch ±Spread. Les fragments plus courts que Rate ne sont pas remplis. Pas encore de degrés de gamme.
- Ornament: Flam ou Grace (pas les deux simultanément), position ±% de grille, vélocité relative, nombre et alternance pitch ±1/0. Chance de note n'est pas émulée; aucune conversion trompeuse en vélocité. Réapplication ajoute des notes via un nouveau snapshot.
- Recombine: tri chronologique puis pitch stable; permutation Position/Pitch/Duration/Velocity, Shuffle déterministe, Mirror puis Rotate. Pas Rotate on Grid ni nouveau reseed automatique à chaque application.
- Span: Legato vers prochain départ sélectionné ou fin de plage native, Tenuto conserve durée, Staccato = moitié du plus petit écart positif; offset/variation signés en ticks de grille. Refus si durée négative ou chevauchement ambigu. Distribution aléatoire indépendante.
- Velocity Shaper: enveloppe linéaire à trois points fixes (début/milieu/fin) manipulables, vélocités min/max, répétitions et décalage par grille. Pas insertion libre de breakpoints, courbes ou Division personnalisée.
- Humanize: ±Amount% de grille, PRNG local explicite; ne prétend pas reproduire celui de Live. Pas de vélocité aléatoire implicite.
- Rhythm: pas, hits, seed, pitch, vélocité, longueur/step; pas Pattern exhaustif, Split/Shift/Accent.
- Euclidean: une voix uniquement; pas les quatre voix/onglets officiels.
- Seed: grille à slots, densité, pitch/velocity min/max et seed; pas durée aléatoire ni Voices. Gamme non appliquée automatiquement.
- Shape: Line/Sine/Triangle, nombre de notes, pitch min/max et longueur; pas dessin libre, jitter/tie/densité du manuel.
- Stacks: un accord choisi (Major/Minor/Sus2/Seventh), répété en segments égaux; pas édition individuelle/progression/renversements/Tonnetz/banks .stacks.
- Arpeggiate: pas 18 styles/Distance/degrés; Chop: pas gaps/emphasis/stretch/variation; Quantize: pas choix end/both. Grilles locales ne modifient pas silencieusement la grille REAPER. Strum utilise toujours la grille native.

Tous ces outils ont une utilité réelle mais leurs panneaux restent partiels: les contrôles de choix/nombres/rotatifs/enveloppe et previews sont originaux, pas une équivalence graphique complète. Les paramètres partagés entre outils restent partagés dans cette version, pas des presets indépendants.

## Sûreté

Contexte de session gelé AVANT premier preview; répétitions depuis original. Un changement de target ne peut pas écrire le nouveau take dans le même geste. Changement des octets MIDI (sélection comprise), item offset/playrate/bornes ou plage temps refuse/restitue selon les contrôles Core. Aucune activation de projet.

Une annulation refusée garde session et journal; Escape/close ne déclarent pas une restauration inexistante. La commande contextuelle «Archive conflict and accept current MIDI» demande confirmation, conserve exactement les octets MIDI actuels (y compris ancien preview), archive et relit le journal, puis libère le panneau. Aucune réconciliation silencieuse des flags de sélection. Reset change les paramètres uniquement: le statut avertit explicitement si l'ancien preview reste audible.

Le CC123 terminal exact est replacé après les événements non vides à la frontière, notamment note-offs, avant le terminateur vide. Les dépassements de frontière et les autres CC/expression restent refusés. Nouvelles opérations structurelles utilisent volontairement les gardes strictes de Chop; elles peuvent refuser davantage de données que les outils historiques.

## Plage générateur

`PanelContext.lua` prend la time selection intersectée avec l'item; sinon l'item. Les deux bornes passent par `MIDI_GetPPQPosFromProjTime(take,time)`, résolution par différence `MIDI_GetPPQPosFromProjQN`. Aucun calcul position-offset au tempo supposé. Le fallback à l'item n'est pas un loop-brace Ableton: répétitions source/loop-source peuvent être refusées si elles dépassent le marqueur. Les sous-plages négatives/invalides sont refusées par le générateur. La fenêtre affiche la plage source PPQ réellement proposée.

## Vérification et blocage natif

Commande:

    python tests/run_midi_expansion_unit.py

Exécute Lua 5.4 réel via `/home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py`. Les tests d'intégration utilisent les vrais Core/Adapter/Transformations/Generators et vrais fichiers de recovery, mais des APIs REAPER simulées: ne pas appeler ceci validation host. Rapport hashé: `qa/midi-expansion-unit.tsv`. Les sept scripts panel/helpers compilent.

    xvfb-run -a -s '-screen 0 1400x1000x24' python tests/run_midi_expansion_gui.py --reaper /home/randomaccessmemories/.hermes/cache/scratch/reaskii-native/reaper_linux_x86_64/REAPER/reaper

BLOQUÉ: ce binaire fourni est absent, `FileNotFoundError` avant lancement. Aucun nouveau PASS natif ni screenshot réel. Recherche locale cache/Downloads/opt/usr-local/archives sans copie utilisable; aucune installation tentée. Le nouveau runner GUI et fixture sont fournis mais non acceptés tant qu'ils n'ont pas réellement tourné. Il vise boutons réels X11, transformations, cinq générateurs sur clip vide, Auto OFF, undo, annulation et édition externe. Des ajustements du harness peuvent encore être requis.

L'ancien `midi_fidelity_unit.lua` passe les dix premiers groupes, échoue son dernier groupe aux coordonnées fixes du layout ancien; il n'a pas été modifié. L'ancien runner et les preuves `qa/midi-fidelity-*` restent historiques, pas validation du code changé.

## Références inspectées

Manuel officiel récupéré: https://www.ableton.com/en/live-manual/12/midi-tools/ ; screenshots utilisateur `upload_bjmi03ke.png` et `upload_03sl0kan.png` vus. Images officielles de Arpeggiate/Chop/Connect/Ornament/Recombine/Span/Velocity Shaper/Rhythm/Seed/Shape/Stacks récupérées et vues en planche scratch `midi-expansion-references.png`. Graphisme original seulement; aucune image propriétaire intégrée au produit. La planche montre clairement les divergences encore ouvertes (pads, sliders, choix et graphes plus riches). Aucun screenshot de notre nouveau runtime ne remplace la QA native manquante.

## Inventaire restant — non terminé

Time Warp complet (courbe vitesse 1–3 breakpoints, intégration temps, Preserve Range, Include End, Quantize), MPE vérifié par autre worker, sous-paramètres listés ci-dessus, clips édition nom/bornes/durée (actuellement lecture seule), Launch/Session host mismatch, imbrication/placement native, Docker adversarial, Windows, mesures Live exports/gestes/PRNG. Les tests Lua ne ferment aucune de ces gates.
