/// Configuración del tema táctico OLED Black (#000000) y estándares ergonómicos para uso con guantes.
class StgOledThemeSpec {
  static const int backgroundHex = 0xFF000000; // OLED Puro Negro (0 mW en píxeles apagados)
  static const int surfaceHex = 0xFF121212;
  static const int highContrastTextHex = 0xFFFFFFFF;

  // Colores normados Triaje START (SCI-207)
  static const int startRojoHex = 0xFFFF1744;
  static const int startAmarilloHex = 0xFFFFD600;
  static const int startVerdeHex = 0xFF00E676;
  static const int startNegroHex = 0xFF424242;

  // Simbología SCI-201
  static const int sciPcOrangeHex = 0xFFFF6D00;
  static const int sciStagingYellowHex = 0xFFFFEA00;

  /// Tamaño mínimo de botón táctico para operación con guantes de rescate (>= 60x60 dp)
  static const double minGloveButtonWidthDp = 64.0;
  static const double minGloveButtonHeightDp = 64.0;

  /// Regla de UX táctica: máximo 3 toques para completar y despachar cualquier acción crítica
  static const int maxCriticalFlowTaps = 3;
}
