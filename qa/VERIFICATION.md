# Vérification de ReaSkii 0.1.0

## Résultat réellement exécuté

- Moteur : REAPER 7.84, Linux x86_64, installation portable dédiée sous Xvfb.
- 10 tests Python de contrat/structure/assets/paquet : passés.
- 410 scénarios TCP natifs de géométrie WALTER, 22 568 assertions au total avec les contrôles d'indentation : aucun échec.
- TCP de 960, 640 et 320 pixels, layouts par défaut et A/B/C à 100/150/200 %, quatre options « keep », hauteurs réduites, armement et modes de pan/stereo/dual pan.
- Smart folder indent ON/OFF vérifié nativement de profondeur 0 à 6 dans le TCP (A, 100 %) et le MCP (A/B/C, 100/150/200 %). Les enveloppes utilisent le même accumulateur arrondi et ont été inspectées dans le rendu réel ; leur géométrie n'est pas mesurée automatiquement.
- Après revue indépendante, la hauteur minimale MCP a été corrigée pour appliquer le facteur HiDPI à l'indentation. Tous les rapports natifs ont été régénérés après cette correction.
- Ajusteur ouvert par l'action standard 42234. Un clic souris réel sur la case pleine ligne a modifié le paramètre ; une nouvelle instance REAPER a restauré sa valeur persistée.
- ZIP reconstruit deux fois : SHA-256 identique.
- Les 2 892 assets de reARK X sont identiques octet par octet à l'archive d'origine.

Les assertions de non-chevauchement représentent une grande partie du total : ce ne sont pas 22 568 fonctionnalités distinctes. Les contrôles absents faute de place restent explicitement distingués des contrôles visibles.

## Limites et comportements préexistants

Les fonctions nouvelles n'ont pas été exécutées dans le REAPER Windows habituel d'Arthur : il doit rester disponible pour son travail. La validation native ci-dessus porte sur le même moteur WALTER, sous Linux ; le rendu des polices et certains détails de plateforme peuvent différer.

Pour des panneaux extrêmement étroits, le repli vertical du thème original est conservé. Les rapports enregistrent ces replis, notamment avec les grands mètres du layout C à 200 %. Un contrôle « keep » ne peut pas être affiché si le panneau ne dispose plus de place pour lui.

Option pleine ligne OFF : trois anciens cas de nom invisible ont été reproduits avec l'archive originale non modifiée, puis caractérisés explicitement dans les tests :

- 640 px, layout 200%_C ;
- 320 px, layout 150%_A ;
- 320 px, layout 200%_B.

Leur preuve est dans `baseline-narrow*.txt`. Le mode pleine ligne ON garde le nom visible dans les scénarios testés. Aucune correction générale des anciens layouts n'est prétendue ici.

## Fichiers de preuve

- `summary.json` : synthèse calculée à partir des marqueurs DONE et du nombre de scénarios réellement enregistrés.
- `native-{960,640,320}.tsv` : chaque cas, géométries et assertions.
- `adjuster-test.txt` : clic et persistance dans une nouvelle instance.
- `theme-preview.png`, `adjuster-defaults.png` : captures de REAPER réel, pas des maquettes.

Le périphérique audio du serveur n'est pas utilisé ; ces essais valident le thème, pas le traitement audio ou une latence temps réel.
