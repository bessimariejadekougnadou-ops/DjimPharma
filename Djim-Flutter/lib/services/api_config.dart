class ApiConfig {
  const ApiConfig._();

  // Adresse IP Wi-Fi actuelle de votre PC :
  static const String currentPcWifiIp = '192.168.1.73';

  // Mémorise l'URL active pour éviter les délais d'attente répétés
  static String? _workingBaseUrl;

  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;

    if (_workingBaseUrl != null) return _workingBaseUrl!;

    // Sur PC (Windows / Web) ou mobile branché en USB avec adb reverse :
    // 127.0.0.1 répond instantanément et ne dépend d'aucun changement d'IP réseau.
    return 'http://127.0.0.1:8000/api';
  }

  // URL de secours sur le réseau Wi-Fi local si le câble USB est débranché
  static String get wifiBaseUrl => 'http://$currentPcWifiIp:8000/api';

  /// Mémorise l'adresse qui a fonctionné pour accélérer les requêtes suivantes
  static void markSuccess(String url) {
    if (url.contains(currentPcWifiIp)) {
      _workingBaseUrl = wifiBaseUrl;
    } else if (url.contains('127.0.0.1')) {
      _workingBaseUrl = 'http://127.0.0.1:8000/api';
    }
  }

  /// Réinitialise l'adresse mémorisée en cas d'erreur de connexion
  static void resetWorkingUrl() {
    _workingBaseUrl = null;
  }
}



