# Synchronisation APM V2.10.2 — 17 octobre 2026

Source : kit actif `Workspace.APM_DistributionKits.APM_Kit`, lu par MCP Roblox Studio en mode Edit. L'attribut du kit et le module Release indiquent `2.10.2`, canal stable. Aucun point de restauration n'a été utilisé comme source. Aucun script du kit n'a été exécuté pour l'export.

## Contenu

- 214 instances : 177 ModuleScript, 3 Script, 3 LocalScript, 27 Folder, 2 Model et 2 StringValue.
- 183 sources, total distribué de 2 405 061 octets UTF-8.
- Sept READ ME complets : fr, en, es, pt, de, ru, zh, plus le sélecteur de langue.
- Classes, hiérarchie, attributs, tags, Archivable, Enabled, RunContext et valeurs StringValue décrits dans manifest.json.
- Dossiers vides et scripts possédant leurs propres enfants préservés par le projet Rojo explicite.

## Comparaison avec l'ancien main

Référence : `77094cf677d51f49748962b6c8d7893a2ba80de0` (103 fichiers vérifiés). L'ancien dépôt annonçait `2.1.0-preview.1`.

Par chemin d'instance, les 78 scripts de l'ancien projet Rojo existent encore : 56 sources changées, 22 strictement identiques après anonymisation ; le kit actif ajoute 105 sources. Le dépôt est reconstruit à partir du kit actif : les anciens contenus non représentatifs sont remplacés.

Branche de sécurité : `backup/apm-before-2.10.2-2026-10-17`, conservant exactement l'ancien main.

## Anonymisations intentionnelles

Ces substitutions sont appliquées uniquement à la copie exportée, avant son hachage :

- `APM_Core/Server/Settings`, lignes 37, 38 et 50 : trois exemples commentés de comptes Dev/Owner remplacés par l'exemple générique `123456789`.
- `APM_Core/ClientTemplates/APM_Client/Pages/Home` : un crédit personnel remplacé par `APM contributors`.
- `READ ME!!!/0 - Langue · Language · Idioma · Língua · Sprache · Язык · 语言` : un crédit remplacé.
- Chacun des sept guides de langue : deux crédits remplacés.

Soit 10 sources concernées, 16 mentions d'auteur et 3 exemples de comptes. Les identifiants originaux et le pseudonyme ne sont pas consignés dans le dépôt. Les 173 autres sources sont identiques à Studio sans transformation. La logique des scripts et la configuration exécutable n'ont pas été modifiées.

Le contrôle du candidat n'a détecté aucun secret, email, webhook privé, URL privée ou identifiant personnel restant. Les noms de clés, exemples génériques, identifiants d'assets et endpoints publics de fournisseurs sont conservés.

## Validation

- SHA-256 calculés directement dans Studio par un vérificateur Luau indépendant après les mêmes anonymisations, puis comparés aux octets du dépôt : 183 sources attendues.
- Métadonnées comparées au kit actif pour les 214 instances.
- Contrôle de tous les blocs d'export : aucun trou, chevauchement, doublon ni perte d'octets.
- `python build.py`, `python build.py --check` et les 8 tests d'intégrité du builder réussis.
- Les valeurs chiffrées de la validation sont consignées dans `validation.json` ; les empreintes de chaque source sont dans `manifest.json`.

Il s'agit d'une vérification de fidélité des sources et de la structure. Aucun test en jeu, import Rojo dans Studio, enregistrement de place, publication Roblox ou lecture de DataStore n'a été effectué. Le projet Studio est resté inchangé. Le projet Rojo est généré et contrôlé localement ; aucune compilation avec l'exécutable Rojo n'est revendiquée.
