# ReaSkii Device Rack — prototype vertical slice

## Intention

Reproduire la logique du Device View d'Ableton en bas de l'écran, dans une fenêtre REAPER dockable : chaîne de devices de la piste sélectionnée de gauche à droite, device sélectionné, paramètres choisis explicitement par l'utilisateur, contrôles de preview manipulables, et affectation aux paramètres des effets MIDI, démontrée avec un LFO MIDI JSFX original.

Références inspectées : manuel Live 12, section 23.1 Device View et 24.1.2 Plug-In Configure Mode ; images officielles `DeviceViewDevicesL12.png`, `VstPlugInTrackViewL12.png`, `VstPlugInConfigureModeL12.png`. La logique visuelle est reproduite avec des primitives originales, sans asset propriétaire.

## Premier jalon livrable

1. Fenêtre `ReaSkii Device Rack`, compagnon flottant de 1200x340, avec bascule Docker dans le menu contextuel. Le docker REAPER garde actuellement sa hauteur par défaut (44 px mesurés), donc le placement automatique en bas à hauteur utile n'est pas résolu ; le panneau flottant est le mode utilisable.
2. Bandeau de chaîne : chaque FX de la piste, nom, bypass, sélection. Flèches de défilement si la chaîne dépasse la largeur.
3. Device sélectionné : contrôles de preview configurés, rendus en sliders horizontaux avec poignée triangulaire, valeur formatée par REAPER, toggles pour paramètres bistables.
4. Bouton **Configure** : liste des paramètres disponibles, ajout/retrait, réordonnancement, état explicite. La configuration est enregistrée dans le projet REAPER (ProjExtState), clé GUID piste + GUID FX, donc stable après renommage et déplacement.
5. Bouton **Add MIDI LFO** : insère `JS: ReaSkii/ReaSkii MIDI LFO` sur la piste et le sélectionne. Ses paramètres Rate, Shape, Depth, Center, CC, Channel, Sync et Division sont assignables aux previews comme n'importe quel effet MIDI.
6. LFO JSFX original : CC temps réel, formes sine/triangle/square/random, profondeur, centre, canal, CC, mode Free/Sync, division musicale. Il ne prétend pas reproduire le LFO Max for Live d'Ableton.

## Hors périmètre de ce jalon

- Glisser-déposer de devices, réordonnancement de la chaîne, presets, A/B, X-Y field.
- Plusieurs cibles par macro, min/max, inversion, variations, randomisation.
- Routage MIDI/audio avancé, MPE, M4L.
- Parité graphique ou comportementale mesurée avec Live. Les gestes et valeurs restent à comparer.
- Installation automatique sur une autre machine.

## Architecture

- `scripts/device/ReaSkii_DeviceRackModel.lua` : pur Lua, sans REAPER/gfx, sérialisation des contrôles, ajout/retrait/déplacement, validation.
- `scripts/device/ReaSkii_DeviceRackStore.lua` : lecture/écriture ProjExtState, clés GUID.
- `scripts/device/ReaSkii_DeviceRack.lua` : entrée REAPER, boucle gfx, docking bas, cible piste.
- `scripts/device/ReaSkii_DeviceRackUI.lua` : rendu, hit-testing, Configure, sliders, chaîne.
- `effects/ReaSkii/ReaSkii MIDI LFO.jsfx` : effet MIDI original.
- `tests/device_rack_unit.lua` : modèle pur.
- `tests/device_rack_gui.lua` + `tests/run_device_rack_gui.py` : fixture REAPER réel, X11, captures.
- `docs/DEVICE-RACK.md` : ce document, mis à jour avec les preuves.

## Contrat de sûreté

Le panneau ne modifie que des paramètres FX de la piste sélectionnée. Il ne déplace, ne supprime et ne recrée aucun device existant. L'insertion du LFO est une action explicite, annulable par l'Undo REAPER. Aucun accès projet, aucune écriture MIDI, aucun fichier de configuration global. Les erreurs d'API sont affichées dans la barre d'état, pas masquées.

Une configuration orpheline (FX supprimé, projet différent) est ignorée et laissée intacte ; aucune suppressions automatique. Les paramètres hors plage sont filtrés à la lecture.

## Critères d'acceptation

- Le modèle round-trip tabs, retours ligne, backslashes et accents.
- Une config survit à la fermeture/réouverture du panneau et au redémarrage de REAPER sur le même projet.
- Le panneau suit le changement de piste sélectionnée sans écrire sur l'ancienne.
- Configure ajoute, retire et réordonne les paramètres ; le rendu correspond à la configuration.
- Le drag et la molette changent le paramètre réel, avec Shift plus fin ; le double-clic remet la valeur par défaut.
- Le LFO s'insère réellement comme JSFX, expose ses paramètres, et ceux-ci sont assignables.
- Preuve native Xvfb avec captures et rapport hashé, plus suite Lua. Les limites Windows et parité Live restent explicites.

## Preuves du prototype

- `python tests/run_device_rack_unit.py` : modèle 7, store 4, controller 7, UI 4. Rapport `qa/device-rack-unit.tsv`.
- `xvfb-run … python tests/run_device_rack_native.py --reaper …` : 13 contrôles REAPER réels, dont chargement du JSFX avec 12 paramètres, persistance ProjExtState, écriture de paramètre, insertion et Undo. Rapport `qa/device-rack-native.tsv`.
- `xvfb-run … python tests/run_device_rack_gui.py --reaper …` : 12 contrôles X11 réels, dont Configure, ajout d'un paramètre, drag, molette, Shift molette, sélection de device et Add MIDI LFO. Rapport `qa/device-rack-host.tsv`, captures `qa/device-rack-*.png`.

Non mesuré : émission CC du LFO pendant la lecture, placement Docker automatique en bas, comportement Windows, glisser-déposer des devices, parité Live. Le JSFX charge et expose ses paramètres, mais aucun enregistrement de sortie MIDI n'a été fait.

## Vérification MOA

Revue contradictoire demandée par Arthur avec DeepSeek V4.1 Flash et GLM-5.3-Flash. Sur `opencode-go`, le cache modèles expose `low/high/max`, pas `xhigh` ; le niveau le plus élevé réellement disponible est `max`. Le MOA sera donc lancé en `max` et l'écart sera consigné, sans prétendre avoir utilisé xhigh.
