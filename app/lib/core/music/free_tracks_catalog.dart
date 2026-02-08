/// ShazaPiano - Catalogue des musiques gratuites (domaine public)
///
/// Toutes les musiques ici sont de compositeurs morts depuis >70 ans.
/// Les fichiers MIDI et vidéos sont pré-générés et hébergés sur Firebase Storage.
///
/// NOT connected to existing code. Ready to be integrated.
import 'models.dart';

class FreeTracksCatalog {
  /// Pool complet des musiques disponibles pour la rotation.
  /// Les URLs sont des placeholders - à remplacer par les vrais liens
  /// Firebase Storage une fois les vidéos pré-générées.
  static const String _storageBase =
      'https://firebasestorage.googleapis.com/v0/b/shazapiano.appspot.com/o';

  static List<FreeTrack> get allTracks => [
        // ─── FACILE (easy) ───────────────────────────────
        const FreeTrack(
          id: 'fur_elise',
          title: 'Für Elise',
          composer: 'Beethoven',
          difficulty: 'easy',
          durationSec: 180,
          coverAssetPath: 'assets/covers/fur_elise.jpg',
        ),
        const FreeTrack(
          id: 'menuet_sol',
          title: 'Menuet en Sol majeur',
          composer: 'Bach/Petzold',
          difficulty: 'easy',
          durationSec: 90,
          coverAssetPath: 'assets/covers/menuet_sol.jpg',
        ),
        const FreeTrack(
          id: 'prelude_em_chopin',
          title: 'Prélude Op.28 No.4',
          composer: 'Chopin',
          difficulty: 'easy',
          durationSec: 120,
          coverAssetPath: 'assets/covers/prelude_em_chopin.jpg',
        ),
        const FreeTrack(
          id: 'invention_1_bach',
          title: 'Invention n°1 en Do majeur',
          composer: 'Bach',
          difficulty: 'easy',
          durationSec: 85,
          coverAssetPath: 'assets/covers/invention_1_bach.jpg',
        ),
        const FreeTrack(
          id: 'sonate_facile_mozart',
          title: 'Sonate Facile K.545 (1er mvt)',
          composer: 'Mozart',
          difficulty: 'easy',
          durationSec: 210,
          coverAssetPath: 'assets/covers/sonate_facile_mozart.jpg',
        ),

        // ─── MOYEN (medium) ─────────────────────────────
        const FreeTrack(
          id: 'gymnopedie_1',
          title: 'Gymnopédie n°1',
          composer: 'Satie',
          difficulty: 'medium',
          durationSec: 195,
          coverAssetPath: 'assets/covers/gymnopedie_1.jpg',
        ),
        const FreeTrack(
          id: 'gnossienne_1',
          title: 'Gnossienne n°1',
          composer: 'Satie',
          difficulty: 'medium',
          durationSec: 210,
          coverAssetPath: 'assets/covers/gnossienne_1.jpg',
        ),
        const FreeTrack(
          id: 'reverie_debussy',
          title: 'Rêverie',
          composer: 'Debussy',
          difficulty: 'medium',
          durationSec: 300,
          coverAssetPath: 'assets/covers/reverie_debussy.jpg',
        ),
        const FreeTrack(
          id: 'nocturne_op9_2',
          title: 'Nocturne Op.9 No.2',
          composer: 'Chopin',
          difficulty: 'medium',
          durationSec: 270,
          coverAssetPath: 'assets/covers/nocturne_op9_2.jpg',
        ),
        const FreeTrack(
          id: 'valse_la_min_chopin',
          title: 'Valse en La mineur',
          composer: 'Chopin',
          difficulty: 'medium',
          durationSec: 180,
          coverAssetPath: 'assets/covers/valse_la_min_chopin.jpg',
        ),
        const FreeTrack(
          id: 'prelude_do_bach',
          title: 'Prélude en Do majeur BWV 846',
          composer: 'Bach',
          difficulty: 'medium',
          durationSec: 150,
          coverAssetPath: 'assets/covers/prelude_do_bach.jpg',
        ),
        const FreeTrack(
          id: 'canon_re_pachelbel',
          title: 'Canon en Ré (arr. piano)',
          composer: 'Pachelbel',
          difficulty: 'medium',
          durationSec: 240,
          coverAssetPath: 'assets/covers/canon_re_pachelbel.jpg',
        ),

        // ─── DIFFICILE (hard) ────────────────────────────
        const FreeTrack(
          id: 'clair_de_lune',
          title: 'Clair de Lune',
          composer: 'Debussy',
          difficulty: 'hard',
          durationSec: 300,
          coverAssetPath: 'assets/covers/clair_de_lune.jpg',
        ),
        const FreeTrack(
          id: 'arabesque_1',
          title: 'Arabesque n°1',
          composer: 'Debussy',
          difficulty: 'hard',
          durationSec: 270,
          coverAssetPath: 'assets/covers/arabesque_1.jpg',
        ),
        const FreeTrack(
          id: 'sonate_clair_lune',
          title: 'Sonate au Clair de Lune (1er mvt)',
          composer: 'Beethoven',
          difficulty: 'hard',
          durationSec: 360,
          coverAssetPath: 'assets/covers/sonate_clair_lune.jpg',
        ),
      ];

  /// Nombre total de musiques dans le pool
  static int get totalTracks => allTracks.length;

  /// Recherche par ID
  static FreeTrack? findById(String id) {
    try {
      return allTracks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Filtrer par difficulté
  static List<FreeTrack> byDifficulty(String difficulty) {
    return allTracks.where((t) => t.difficulty == difficulty).toList();
  }

  FreeTracksCatalog._();
}
