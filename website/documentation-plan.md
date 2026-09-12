# Documentation autonome de PerfChecker : plan V1

État du 12 septembre 2026. Ce document est un plan de livraison ; les cases non
cochées ne décrivent pas des fonctionnalités déjà qualifiées.

## Décision

Un site PerfChecker unique, regroupant moteur, packages d'interface, extensions,
collecteurs et qualification. Sources auprès du code, génération Documenter.jl,
rendu DocumenterVitepress. Pas de dépendance au site Julia Constraints pour construire
ou consulter ce site. La documentation reste un environnement de développement :
elle ne doit pas devenir une dépendance du moteur ou des workers.

Les extensions d'intégration Documenter servent à publier les résultats de l'utilisateur.
Il ne faut pas le confondre avec le site qui documente PerfChecker lui-même.

## Point de départ vérifié

- Le laboratoire possède désormais `website/make.jl`, des pages, un thème, une recherche
  locale et une base autonome Documenter/VitePress. Il faut les terminer, pas
  maintenir une deuxième copie du contenu.
- Julia Constraints utilise les mêmes deux outils, une page d'accueil, des parcours
  thématiques et un index multi-package. Son `make.jl` tolère les avertissements et
  sa configuration VitePress les liens morts : ne pas reprendre ces tolérances.
- Les dernières versions taguées vérifiées sont Documenter 1.19.0 et
  DocumenterVitepress 0.3.5. Elles ont été résolues ensemble localement. Leur simple
  résolution ne remplace pas le build, les doctests et l'inspection du résultat.
- Le build HTML a ensuite réussi sous Windows avec ces versions et Node 22.19.
  Une étape VitePress explicite corrige le build Windows sauté par le moteur Node
  embarqué. Cela ne vaut pas une revue visuelle ou une qualification de toute l'API.
- `docs/Project.toml` de Julia Constraints ne fixe pas de compatibilité Documenter :
  ses sources seules ne prouvent donc pas la version du dernier site déployé.
- Le tutoriel Bibliography contient désormais une capture vidéo réelle du parcours
  Oxygen, ses sous-titres, la sélection et le résultat photographiés. Un graphique
  WGLMakie permet d'inspecter hors ligne 50 mesures conservées avec leur provenance.
  Les captures VS Code et Pluto montrent maintenant une exécution réelle du même
  export. Le parcours Pluto passe huit contrôles de navigateur, dont la sauvegarde
  après rechargement ; VS Code mesure un seul des deux items découverts. Le dialogue
  REPL a été exécuté jusqu'au rapport ; sa capture visuelle reste à compléter.
- L'index `@autodocs` couvre les bindings publics de PerfChecker, également
  réexportés par les satellites. Les absences du relevé initial ont reçu une
  docstring ; `test/public_api.jl` vérifie maintenant que chaque export est défini
  et documenté. Les méthodes spécifiques des satellites restent à relire pour
  vérifier leurs arguments et garanties, au-delà de ce contrôle structurel.
- Les nouveaux points d'entrée `discover_testitems` et `run_testitems` documentent
  désormais leurs filtres, résultats, effets, erreurs et garanties d'isolation.
- Le premier tutoriel utilise désormais `examples/first-check`, un package livré
  avec trois items ordinaires, de performance et fonctionnels. Son exécution est
  incluse dans la qualification native ; son résultat doit être vérifié.

## Navigation

La barre supérieure est regroupée en quatre menus : **Get started**,
**Use PerfChecker** (interfaces et guides), **Reference**, **Project**.
Sous 1280 pixels, le menu compact natif de VitePress prend le relais. Les pages
restent accessibles dans la barre latérale et la recherche. Les contrôles de
navigateur couvrent sept largeurs, de 390 à 1920 pixels, et la navigation clavier.

Les parcours suivants structurent les pages et la barre latérale ; ils ne sont
pas huit menus supplémentaires en haut du site.

1. **Accueil** : rôle de PerfChecker, exemple concret de régression détectée, accès
   immédiat à « Premier résultat », « VS Code », « CI/CD » et « Packages ».
2. **Démarrer** : installation minimale ; choix d'interface ; premier check complet ;
   explication d'un résultat ; compatibilités et environnement mesuré.
3. **Tutoriels** : cas exécutables progressifs, avec leurs fichiers téléchargeables.
4. **Guides pratiques** : sélection, budgets, baselines, matrices, diagnostics,
   annulation, export et dépannage.
5. **Interfaces et packages** : VS Code en premier, puis CLI/REPL, Web, Pluto,
   visualisations et insertion des résultats dans Documenter.
6. **Comprendre les mesures** : bruit, compilation, warmup, répétitions, allocations,
   exactitude fonctionnelle, contrôleur/workers, provenance et limites d'attribution.
7. **Référence** : API par composant, schémas, commandes, configuration, tags,
   collecteurs, compatibilités effectivement qualifiées et formats d'export.
8. **Contribuer et publier** : architecture, extension ou package, contrats partagés,
   qualification, rédaction, capture, dépréciations et versions.

La recherche doit trouver les noms d'API, les commandes VS Code et les messages
d'erreur. Les anciens concepts `@check`/`PerfConfig` restent référencés et reliés à
un guide de migration. Les propositions et limitations ne doivent pas encombrer
le démarrage, mais doivent être visibles sur les pages concernées.

## Tutoriels obligatoires

| Parcours | Livrable et vérification |
| --- | --- |
| Premier résultat | Petit package de démonstration livré dans le dépôt ; installation et commandes copiables sans inventer de fonction |
| Tests existants | Même `@testitem` utilisé pour le fonctionnel et la performance ; sélection unitaire ; tags `perf_only`/`test_only` ; comportement amont réel clairement expliqué |
| VS Code | Installation, découverte, sélection, exécution, résultat, source, annulation et correction d'une erreur |
| Régression reproductible | Deux implémentations fixes, oracle correct, baseline, budget, comparaison et verdict expliqué |
| CI/CD | PR qualifiée, résultat invalide, artefacts, versions candidates et promotion d'une collection |
| Machines | Batterie courte, voisins comparables, estimation et incertitude ; exemple de refus ; estimation distincte d'une mesure et d'un verdict CI |
| Julia et dépendance native | Temps, allocations, profil ; exemple C ou bibliothèque native ; Valgrind/Linux et diagnostic indisponible sur une plateforme |
| Web et Pluto | Même corpus et mêmes résultats que CLI ; ouverture, sélection, exécution, consultation et annulation |
| Rapports | Relecture hors ligne, graphiques, export et insertion dans Documenter sans relancer les mesures |

Chaque tutoriel possède un test automatisé associé. Les temps exacts ne servent pas
d'oracle : vérifier structure, sélection, résultat fonctionnel et verdicts contrôlés.
Les démonstrations d'échec attendu doivent être testées comme telles.

## Revue des docstrings

Inventorier types, constructeurs, macros, fonctions exportées et API publiques non
exportées, puis les méthodes ajoutées par chaque extension/package chargé séparément.
Détecter aussi les noms exportés non définis et les anciennes signatures encore
présentes dans les pages. Rattacher chaque entrée à un composant propriétaire.

Pour chaque entrée publique, fournir selon son besoin :

- signature, types et valeurs par défaut ;
- rôle concret, arguments et valeur de retour ;
- effets observables : fichiers écrits, processus lancés, attente, réseau, mutation ;
- erreurs, préconditions, annulation et garanties d'isolation ;
- activation de l'extension ou package à charger ;
- petit exemple vérifié et liens vers les notions ou tutoriels utiles.

Priorité : définition et sélection des items, préparation des environnements,
exécution/annulation, résultats/verdicts, interfaces publiques, puis analyseurs,
exports et compatibilité historique. Les internes complexes méritent des commentaires
d'invariants ; les accesseurs triviaux ne nécessitent pas des paragraphes artificiels.

Une absence de docstring et une docstring qui ne dit rien sont deux défauts distincts.
`checkdocs=:exports` reste activé, mais n'est pas une preuve que chaque export possède
une docstring. Ajouter un contrôle explicite des bindings publics, avec une liste
transitoire d'absences à réduire jusqu'à zéro pour l'API V1 annoncée.

Les pages d'API doivent inclure les modules des satellites réels, sans annoncer
comme installables des packages seulement proposés. Construire les fragments des
environnements incompatibles séparément, puis assembler leurs pages dans le site.

## Captures et démonstrations visuelles

Corpus commun déterministe, chemins neutres, versions consignées, aucune UI fabriquée.
Conserver la recette de capture, le SHA du corpus, les versions, le viewport et le
thème dans un manifeste adjacent aux images.

Galerie minimale :

1. VS Code : découverte et sélection d'un item ;
2. VS Code : régression et accès à sa source ;
3. Oxygen : sélection puis résultat ;
4. Oxygen : disposition étroite ;
5. Pluto : notebook ouvert et résultat chargé ;
6. REPL : sélection et rapport lisibles ;
7. Makie : distribution et profil/allocations ;
8. Documenter : rapport publié depuis un bundle.

Inspecter les images à leur taille de lecture, avec légende et texte alternatif.
Référence claire/sombre par interface qui le supporte. Les captures prouvent
l'affichage ; des assertions distinctes prouvent l'interaction et le résultat.
Une mise à jour de référence visuelle doit être revue, jamais acceptée automatiquement
simplement pour faire passer la CI. Cette approche rejoint ReferenceTests de Makie.

## Ligne éditoriale

Anglais technique simple pour le site, cohérent avec l'existant. Une tâche précise
par page, un résultat observable dès le début, vocabulaire constant. Expliquer les
compromis au moment où ils changent un choix. Supprimer les promesses générales,
les répétitions entre pages, les superlatifs, les introductions génériques et les
listes de fonctionnalités sans exemple. Les références longues peuvent être
exhaustives ; le parcours de démarrage doit rester court.

Chaque capacité indique son état exact : testée sur la matrice annoncée, prise en
charge sous conditions, expérimentale ou seulement proposée. Un outil inventorié
n'est pas nécessairement un collecteur implémenté. Aucun label « V1 stable » avant
la clôture des critères de livraison.

## Qualification et déploiement

`PerfCheckerQualification` fournit le candidat de collection, les contrats communs,
la matrice par dépendances et les preuves. Un résultat ciblé de PR ne peut pas
promouvoir les pages de référence de la collection complète. La documentation
officielle doit provenir d'une qualification complète des versions exactes, de
leurs environnements distincts et de l'artefact de site construit pendant ce run.

Le pipeline localement préparé sépare build et publication, conserve les manifests
résolus et vérifie le hash du site. La publication est désactivée jusqu'à notre
configuration commune. Préparer ensuite : dépôt et domaine cibles, Pages, URL de
base, versions stable/dev, politique des tags, droits du bot, règles de branches et
conservation des preuves. Un retour arrière redéploie un artefact précédemment
qualifié ; il ne reconstruit pas une ancienne version avec les dépendances du jour.

Une fois le site autonome validé, préparer une table des anciennes URL PerfChecker
de Julia Constraints vers les nouvelles pages. Garder des redirections ou pages de
transition plutôt que de casser les liens existants. Ce basculement est distinct de
la création du site ; aucune suppression dans Julia Constraints n'a été effectuée.

## Ordre de livraison et critères de clôture

| Étape | Critère de sortie |
| --- | --- |
| 1. Contrats et inventaire | Découpage retenu ; liste API/pages/capacités avec propriétaire ; état actuel consigné |
| 2. Démarrage et VS Code | Un utilisateur part d'un dossier neuf et obtient un résultat avec les fichiers fournis |
| 3. API et tutoriels | API V1 entièrement documentée ; exemples automatiques ; signatures cohérentes |
| 4. Interfaces et galerie | Parcours exécutés ; captures réelles reproductibles et inspectées |
| 5. Site complet | Build strict, liens internes, recherche, navigation, thèmes, mobile et contenu relus |
| 6. Qualification | Collection exacte verte sur Windows/Linux ; limites publiées ; aucune preuve manquante masquée |
| 7. Publication commune | Destination/versions configurées ; premier déploiement vérifié ; retour arrière possible |

Conserver les tests rapides d'exemples à chaque PR ; réserver campagnes coûteuses et
captures complètes aux changements concernés et à la qualification de release.
Un lien externe temporairement indisponible produit un diagnostic distinct d'un
lien interne cassé ; aucune tolérance générale aux avertissements ne doit les masquer.

## Sources examinées

- [Julia Constraints : sources du site](https://github.com/JuliaConstraints/JuliaConstraints.github.io/tree/main/docs)
- [Documenter 1.19.0](https://github.com/JuliaDocs/Documenter.jl/releases/tag/v1.19.0)
- [DocumenterVitepress 0.3.5](https://github.com/LuxDL/DocumenterVitepress.jl/releases/tag/v0.3.5)
- [Déploiement Documenter](https://documenter.juliadocs.org/stable/man/hosting/)
- [Tests de référence Makie](https://github.com/MakieOrg/Makie.jl/tree/master/ReferenceTests)
