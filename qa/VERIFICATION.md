# Vérification de ReaSkii 0.1.1

## Résultat réellement exécuté

- Moteur : REAPER 7.84, Linux x86_64, installation portable dédiée sous Xvfb.
- 11 tests Python de contrat/structure/assets/paquet/preuves géométriques : passés.
- 570 scénarios TCP natifs de géométrie WALTER, 31 204 assertions au total avec les contrôles d'indentation : aucun échec.
- TCP de 960, 640, 540 et 320 pixels, layouts par défaut et A/B/C à 100/150/200 %, quatre options « keep », hauteurs réduites, armement et modes de pan/stereo/dual pan.
- Régression 0.1.0 reproduite par un nouveau test : 35 assertions de visibilité en échec sur les pistes compactes à 640 px avant le correctif. Les marges de 7 px exigeaient 61 px pour deux rangées de 20 px. Le correctif réduit uniquement les marges verticales en mode pleine ligne, sans imposer une nouvelle hauteur aux pistes.
- Visibilité obligatoire volume/pan/routing/FX/enveloppes à 50/58/61/65 px multipliés par le scale sur A ; contrôles vérifiés à 640/960 px et à 540 px au scale 1. Les autres scénarios ne prétendent pas que tous les contrôles tiennent. Mode de référence supplémentaire à 50/58/88 px : keep volume/pan ON, colonne FX droite, entrée et FX d'entrée explicitement visibles à 540/640/960 px.
- Vérification supplémentaire des preuves enregistrées : 203 rectangles de contrôles obligatoires sont contenus dans le panneau réel et ont au moins 19 px de hauteur. Ce contrôle Python relit les TSV ; il ne constitue pas un lancement supplémentaire de REAPER.
- Smart folder indent ON/OFF vérifié nativement de profondeur 0 à 6 dans le TCP (A, 100 %) et le MCP (A/B/C, 100/150/200 %). Les enveloppes utilisent le même accumulateur arrondi et ont été inspectées dans le rendu réel ; leur géométrie n'est pas mesurée automatiquement.
- Après revue indépendante, la hauteur minimale MCP a été corrigée pour appliquer le facteur HiDPI à l'indentation. Tous les rapports natifs ont été régénérés après cette correction.
- Ajusteur ouvert par l'action standard 42234. Un clic souris réel sur la case pleine ligne a modifié le paramètre ; une nouvelle instance REAPER a restauré sa valeur persistée.
- ZIP reconstruit deux fois : SHA-256 identique.
- Les 2 892 assets de reARK X sont identiques octet par octet à l'archive d'origine.

Les assertions de non-chevauchement représentent une grande partie du total : ce ne sont pas 31 204 fonctionnalités distinctes. Elles ne remplacent pas les assertions de visibilité obligatoire introduites pour les pistes compactes. Les contrôles absents faute de place restent explicitement distingués des contrôles visibles.

## Limites et comportements préexistants

Les fonctions nouvelles n'ont pas été exécutées dans le REAPER Windows habituel d'Arthur : il doit rester disponible pour son travail. La validation native ci-dessus porte sur le même moteur WALTER, sous Linux ; le rendu des polices et certains détails de plateforme peuvent différer.

Les demandes de très petite hauteur peuvent être bornées par REAPER, notamment lors de l'armement : un `I_HEIGHTOVERRIDE` de 25 ne prouve pas un panneau réel de 25 px. Les cas compacts obligatoires utilisent les hauteurs effectivement mesurées dans `tcp.size`. Le calcul de marge réserve 1 px au bord : à 61 px la marge reste légèrement réduite (6,67 px à 100 %), et revient à 7 px à 62 px. La revue n'a pas identifié de défaut fonctionnel de ce comportement.

Pour des panneaux extrêmement étroits, le repli vertical du thème original est conservé. Les rapports enregistrent ces replis, notamment avec les grands mètres du layout C à 200 %. Un contrôle « keep » ne peut pas être affiché si le panneau ne dispose plus de place pour lui.

Option pleine ligne OFF : trois anciens cas de nom invisible ont été reproduits avec l'archive originale non modifiée, puis caractérisés explicitement dans les tests :

- 640 px, layout 200%_C ;
- 320 px, layout 150%_A ;
- 320 px, layout 200%_B.

Leur preuve est dans `baseline-narrow*.txt`. Le mode pleine ligne ON garde le nom visible dans les scénarios testés. Aucune correction générale des anciens layouts n'est prétendue ici.

## Fichiers de preuve

- `summary.json` : synthèse calculée à partir des marqueurs DONE et du nombre de scénarios réellement enregistrés.
- `native-{960,640,540,320}.tsv` : chaque cas, géométries et assertions.
- `adjuster-test.txt` : clic et persistance dans une nouvelle instance.
- `theme-preview.png`, `adjuster-defaults.png` : captures de REAPER réel avec pistes de 50/58 pixels et réglages par défaut, pas des maquettes.
- `compact-reference.png`, `adjuster-reference.png` : rendu avec keep volume/pan ON, monitoring et entrée activés, pan visible même lorsque le mixer est ouvert. Ce préréglage de démonstration n'est pas présenté comme le défaut du thème.

Le périphérique audio du serveur n'est pas utilisé ; ces essais valident le thème, pas le traitement audio ou une latence temps réel.
