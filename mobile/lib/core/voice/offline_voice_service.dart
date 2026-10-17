/// Servicio de dictado por voz 100% offline para captura manos libres con guantes.
/// También interpreta comandos rápidos de triaje y bloqueos viales.
class OfflineVoiceDictationService {
  bool _isListening = false;
  String _lastTranscript = '';

  bool get isListening => _isListening;
  String get lastTranscript => _lastTranscript;

  void startListening() {
    _isListening = true;
  }

  void stopListening() {
    _isListening = false;
  }

  String simulateTranscript(String spokenText) {
    _lastTranscript = spokenText.trim();
    _isListening = false;
    return _lastTranscript;
  }

  /// Extrae conteos START si el brigadista dicta: "dos rojos tres amarillos un verde"
  Map<String, int> parseSpokenStartCounts(String text) {
    final normalized = text.toLowerCase();
    int extractFor(String colorKeyword) {
      final regex = RegExp(r'(\d+|un|uno|dos|tres|cuatro|cinco)\s+' + colorKeyword);
      final match = regex.firstMatch(normalized);
      if (match == null) return 0;
      final token = match.group(1)!;
      const words = {
        'un': 1,
        'uno': 1,
        'dos': 2,
        'tres': 3,
        'cuatro': 4,
        'cinco': 5,
      };
      return words[token] ?? int.tryParse(token) ?? 0;
    }

    return {
      'ROJO': extractFor('rojo'),
      'AMARILLO': extractFor('amarillo'),
      'VERDE': extractFor('verde'),
      'NEGRO': extractFor('negro'),
    };
  }
}
