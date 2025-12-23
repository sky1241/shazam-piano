/// Domain entity for a processed level result
class LevelResult {
  final int level;
  final String name;
  final String previewUrl;
  final String videoUrl;
  final String midiUrl;
  final String? keyGuess;
  final int? tempoGuess;
  final double? durationSec;
  final String status;
  final String? error;

  const LevelResult({
    required this.level,
    required this.name,
    required this.previewUrl,
    required this.videoUrl,
    required this.midiUrl,
    this.keyGuess,
    this.tempoGuess,
    this.durationSec,
    this.status = 'success',
    this.error,
  });

  bool get isSuccess => status == 'success';
  bool get isError => status == 'error';
  bool get isPending => status == 'pending';
}
