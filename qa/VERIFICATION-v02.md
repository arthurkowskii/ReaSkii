# ReaSkii 0.2.0: vérification

## Périmètre livré

Moteur Reapertips v1.95a Dark, art et polices reARK X, présentation combinée des FX TCP à droite reprise de reARK. Les défauts du moteur sont conservés, sauf le nom pleine première ligne activé à la demande d'Arthur ; Smart folder indent est déjà activé dans Reapertips. Les quatre « keep » restent désactivés par défaut.

Les macros comportementales de référence sont comparées textuellement, avec seulement deux hooks explicites dans `calcTcpSecs` : marges compactes et réservation de la colonne reARK. Les six macros de rendu reçoivent un hook de skin final ; les banques de polices reARK précèdent les overrides utilisateur Reapertips. Les effets de peinture de panneaux Reapertips sont volontairement remplacés, pas présentés comme inchangés.

## Exécution réelle

- REAPER **7.84 Linux**, installation portable isolée sous Xvfb ; aucun essai dans la session laptop.
- **17 tests Python PASS**, dont conservation des 2 892 assets originaux par SHA-256, paramètres de référence, macros, géométrie enregistrée, images custom et paquet réel.
- **531 scénarios TCP**, **42 715 assertions**, **0 FAIL**.
- **180 rectangles essentiels** contenus dans leurs panneaux réels, sur A/B/C à 100 %, aux hauteurs réelles **50/58/61/65 px**, largeurs 540/640/960.
- A/B/C à 100/150/200 % pour le placement, les combinaisons « keep », armement, pan stéréo/dual, colonne reARK activée/désactivée. Largeurs 960/640/540/320.
- Trois vrais inserts JS chargés pour la géométrie de la colonne ; les captures contiennent de vrais plugins JS.
- **191 paramètres déclarés** comparés à leurs défauts, puis valeurs perturbées et remises aux défauts via le vrai script Lua. Sauvegarde créée, restauration exécutée et vérifiée ; une nouvelle personnalisation est conservée à la seconde ouverture.
- MCP : visibilité des labels et des valeurs de volume sur A/B/C × 100/150/200 %, profondeurs 0 à 6 ; contrôle de volume également obligatoire à 100 %. Ce n'est pas un test exhaustif des commandes du mixer.
- Ajusteur ouvert via l'action **42234**, vrai clic sur le nom pleine ligne et persistance vérifiée dans un nouveau processus REAPER.
- Installeur extrait du **vrai ZIP de livraison**, parsé et exécuté avec **PowerShell 7.4.6 sous Linux** dans un bac à sable : **14 contrôles PASS**. Installation neuve, trois scripts, idempotence, refus d'écrasement implicite, mise à jour explicite, sauvegarde identique, réglages non modifiés, paquet incomplet et collision de répertoire refusés sans installation partielle. Cela ne vaut pas exécution de REAPER Windows.

| Largeur TCP | Scénarios TCP | Assertions | FAIL |
|---:|---:|---:|---:|
| 960 | 207 | 20 096 | 0 |
| 640 | 108 | 8 973 | 0 |
| 540 | 108 | 8 542 | 0 |
| 320 | 108 | 5 104 | 0 |

`qa/summary-v02.json` est l'agrégat calculé ; le script rejette les totaux incohérents et les résultats dont les empreintes ne correspondent plus au thème, au scénario Lua ou au script de migration courants. Les anciens `native-*.tsv` et `summary.json` restent les archives 0.1 et ne prouvent pas cette version.

## Suite de l'audit d'assets

- Fonds opaques peints Reapertips neutralisés après rendu : les images reARK restent visibles.
- Boutons **P/p** et **C** originaux générés sans reprendre d'image Reapertips, aux trois échelles et avec trois états. Présence visuelle vérifiée dans la capture avec piste agrandie et fixed lanes activées ; leur présence n'est pas présentée comme un test automatisé de chacun de leurs clics.
- Connecteurs de dossiers : aliases byte-identiques d'images reARK. Les overlays d'images de référence encore absentes doivent être explicitement neutralisés par le skin, sinon le test échoue.
- Layouts graphiques sans dossier reARK correspondant supprimés, ainsi que leurs traductions DPI. Les layouts fonctionnels principaux A/B/C et leurs échelles restent présents.
- Hauteurs et minima du moteur Reapertips conservés volontairement ; pas de retour silencieux à tous les défauts reARK. L'usage de pistes compactes 50/58 px est testé séparément.

## Empreinte du thème testé

`d7d1760e600a3e30dcf63a5a68e29b2cfd9a6c7194c69fd4863bb5951d7d3460`

## Traitement de la contre-revue

- Colonne FX : valeurs personnelles reARK relues sur le laptop en lecture seule, identité `skii_pc` vérifiée : largeur étape 3 (130 px), deux colonnes, hauteur étape 2 (16 px). Position droite imposée par la demande utilisateur. Les défauts sont désormais vérifiés explicitement en natif, en plus de leur correspondance aux déclarations. La géométrie vérifie la largeur utile et la marge droite de 7 px.
- Layouts sans dossiers : garde-fou générique et test ajoutés ; ce point de la revue portait sur un instantané antérieur.
- Signalement MCP de valeurs absentes et d'échelles doubles non reproduit sur la capture actuelle, inspectée en zoom. Les valeurs sont présentes ; les assertions MCP ont néanmoins été renforcées. Pas de remplacement injustifié du moteur mixer par reARK.
- Les remarques « 640 seulement » et « ajusteur par dofile seulement » portaient sur des preuves anciennes : les quatre rapports 0.2 sont régénérés et liés par hash ; le vrai ajusteur est aussi testé via action standard 42234, clic et nouvelle instance.
- Les listes masquées par manque de place ne sont pas présentées comme visibles : `P_UI_RECT` peut ne pas les exposer. Les cas à 100 % avec place suffisante exigent explicitement une colonne visible ; les autres ne constituent pas une couverture universelle de visibilité.

## Limites

Pas de validation runtime Windows finale, de mesure complète EnvCP, de couverture exhaustive des boutons MCP, de toutes les tailles de fenêtres ou de toutes les variantes de layouts. Un panneau trop étroit peut masquer la colonne FX et replier les contrôles selon le moteur Reapertips. Les trois échelles sont testées, mais les assertions obligatoires sur les cinq contrôles compacts concernent les cas A/B/C à 100 % explicités ci-dessus. La couverture de défauts inclut les séparateurs/titres déclarés par le thème, pas 191 fonctionnalités indépendantes. La remise aux défauts intervient à l'ouverture de l'ajusteur après installation, pas à la seule copie du ZIP.

Le dépôt reste privé ; publication Git et état CI distant sont à vérifier séparément des tests locaux. Aucune CI verte n'est déduite d'un push réussi.
