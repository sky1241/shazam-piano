# ShazaPiano — Règles Agent

- Interdits sans accord explicite : nouveaux packages (pubspec/requirements), refactor global, renommages/déplacements massifs, >6 fichiers modifiés par tâche (sauf opérations infra/flatten).
- Flux de réponse obligatoire : PLAN (≤6 lignes) → CHANGEMENTS (diff/fichiers) → VÉRIFICATION (commandes) → TEST MANUEL (≤5 étapes).
- Flutter (`app/`) : respecter Riverpod et la structure lib/core|data|domain|presentation ; si retrofit/api change, régénérer via build_runner si besoin ; audio/streaming → gérer permissions, stop/cancel, timeout, pas de boucle infinie ; null-safety stricte, éviter `dynamic`/`!` sans justification.
- Backend (`backend/`) : pas de refonte lourde ; gérer erreurs/logs proprement ; ne versionner aucun venv/caches/build.
- Pas de nouveaux packages, pas de refactor global ou déplacement massif sans feu vert.
- Utiliser `git mv` pour tout déplacement et conserver l’historique.
