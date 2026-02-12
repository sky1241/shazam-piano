/// ShazaPiano - Service de rotation hebdomadaire déterministe
///
/// Algorithme : seed = year * 100 + weekNumber → shuffle déterministe → pick 6
/// Même résultat sur tous les devices pour la même semaine.
///
/// NOT connected to existing code. Ready to be integrated.
library;

import 'dart:math';

import 'models.dart';
import 'free_tracks_catalog.dart';

class RotationService {
  /// Retourne les 6 musiques de la semaine courante
  static WeeklyRotation getCurrentRotation() {
    final now = DateTime.now();
    return getRotationForDate(now);
  }

  /// Retourne la rotation pour une date donnée
  static WeeklyRotation getRotationForDate(DateTime date) {
    final weekNumber = _isoWeekNumber(date);
    final year = date.year;
    return getRotationForWeek(weekNumber, year);
  }

  /// Retourne la rotation pour un numéro de semaine ISO
  ///
  /// Sélection catégorisée : 2 easy + 2 medium + 2 hard.
  /// Page 1 = 1 facile + 1 difficile (contraste extrêmes).
  /// Pages 2-3 = les 4 restants en ordre aléatoire.
  static WeeklyRotation getRotationForWeek(int weekNumber, int year) {
    final pool = FreeTracksCatalog.allTracks;

    // Seed déterministe basé sur la semaine
    final seed = year * 100 + weekNumber;
    final rng = Random(seed);

    // Séparer par difficulté et shuffle chaque groupe
    final easy = List<FreeTrack>.from(
      pool.where((t) => t.difficulty == 'easy'),
    )..shuffle(rng);
    final medium = List<FreeTrack>.from(
      pool.where((t) => t.difficulty == 'medium'),
    )..shuffle(rng);
    final hard = List<FreeTrack>.from(
      pool.where((t) => t.difficulty == 'hard'),
    )..shuffle(rng);

    // Prendre 2 de chaque
    final pick2Easy = easy.take(2).toList();
    final pick2Medium = medium.take(2).toList();
    final pick2Hard = hard.take(2).toList();

    // Page 1 : 1 facile + 1 difficile (les extrêmes)
    // Pages 2-3 : les 4 restants mélangés
    final remaining = <FreeTrack>[
      pick2Easy[1],
      ...pick2Medium,
      pick2Hard[1],
    ]..shuffle(rng);

    final selected = <FreeTrack>[
      pick2Easy[0], // Page 1 : facile
      pick2Hard[0], // Page 1 : difficile
      ...remaining, // Pages 2-3 : aléatoire
    ];

    // Calculer début et fin de semaine
    final monday = _mondayOfISOWeek(weekNumber, year);
    final sunday = monday.add(const Duration(days: 7));

    return WeeklyRotation(
      weekNumber: weekNumber,
      year: year,
      tracks: selected,
      startsAt: monday,
      endsAt: sunday,
    );
  }

  /// Temps restant avant la prochaine rotation
  static Duration timeUntilNextRotation() {
    final rotation = getCurrentRotation();
    return rotation.timeRemaining;
  }

  /// Vérifie si une musique est dans la rotation courante
  static bool isInCurrentRotation(String trackId) {
    final rotation = getCurrentRotation();
    return rotation.tracks.any((t) => t.id == trackId);
  }

  /// Retourne la prochaine rotation (semaine suivante)
  static WeeklyRotation getNextRotation() {
    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));
    return getRotationForDate(nextWeek);
  }

  // ─── Helpers ISO Week ───────────────────────────────

  /// Calcule le numéro de semaine ISO 8601
  static int _isoWeekNumber(DateTime date) {
    // Trouver le jeudi de la semaine courante
    final dayOfYear = _dayOfYear(date);
    final weekday = date.weekday; // 1=lundi, 7=dimanche
    final thursdayOffset = 4 - weekday;
    final thursdayDayOfYear = dayOfYear + thursdayOffset;

    // Gérer les cas en début/fin d'année
    if (thursdayDayOfYear <= 0) {
      // Semaine appartient à l'année précédente
      final dec31 = DateTime(date.year - 1, 12, 31);
      return _isoWeekNumber(dec31);
    }

    final daysInYear = _isLeapYear(date.year) ? 366 : 365;
    if (thursdayDayOfYear > daysInYear) {
      // Semaine appartient à l'année suivante
      return 1;
    }

    return ((thursdayDayOfYear - 1) ~/ 7) + 1;
  }

  /// Jour de l'année (1-366)
  static int _dayOfYear(DateTime date) {
    final firstDay = DateTime(date.year, 1, 1);
    return date.difference(firstDay).inDays + 1;
  }

  /// Année bissextile
  static bool _isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
  }

  /// Retourne le lundi de la semaine ISO donnée
  static DateTime _mondayOfISOWeek(int weekNumber, int year) {
    // 4 janvier est toujours dans la semaine ISO 1
    final jan4 = DateTime(year, 1, 4);
    final jan4Weekday = jan4.weekday; // 1=lundi

    // Lundi de la semaine 1
    final mondayWeek1 = jan4.subtract(Duration(days: jan4Weekday - 1));

    // Lundi de la semaine demandée
    return mondayWeek1.add(Duration(days: (weekNumber - 1) * 7));
  }

  RotationService._();
}
