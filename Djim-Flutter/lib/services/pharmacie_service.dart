import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class PeriodeGardeInfo {
  final int id;
  final String dateDebut;
  final String dateFin;
  final String zone;
  final String source;
  final String dateVerification;
  final String statutValidation;

  PeriodeGardeInfo({
    required this.id,
    required this.dateDebut,
    required this.dateFin,
    required this.zone,
    required this.source,
    required this.dateVerification,
    required this.statutValidation,
  });

  factory PeriodeGardeInfo.fromJson(Map<String, dynamic> json) {
    return PeriodeGardeInfo(
      id: json['id'] ?? 0,
      dateDebut: json['date_debut'] ?? '',
      dateFin: json['date_fin'] ?? '',
      zone: json['zone'] ?? '',
      source: json['source'] ?? 'ONPT Togo',
      dateVerification: json['date_verification'] ?? '',
      statutValidation: json['statut_validation'] ?? 'valide',
    );
  }
}

class PharmacieItem {
  final int id;
  final String nom;
  final String adresse;
  final String ville;
  final String quartier;
  final String telephone;
  final bool estDeGarde;
  final double? latitude;
  final double? longitude;
  final String? googlePlaceId;
  final String sourceDonnees;
  final String statutVerification;
  final String sourceVerification;
  final String? dateDerniereSynchro;
  final PeriodeGardeInfo? periodeGarde;

  PharmacieItem({
    required this.id,
    required this.nom,
    required this.adresse,
    required this.ville,
    this.quartier = '',
    required this.telephone,
    required this.estDeGarde,
    this.latitude,
    this.longitude,
    this.googlePlaceId,
    this.sourceDonnees = 'local',
    this.statutVerification = 'verifiee_officielle',
    this.sourceVerification = 'ONPT Togo',
    this.dateDerniereSynchro,
    this.periodeGarde,
  });

  factory PharmacieItem.fromJson(Map<String, dynamic> json) {
    return PharmacieItem(
      id: json['id'] ?? 0,
      nom: json['nom'] ?? '',
      adresse: json['adresse'] ?? '',
      ville: json['ville'] ?? '',
      quartier: json['quartier'] ?? '',
      telephone: json['telephone'] ?? '',
      estDeGarde: json['est_de_garde'] ?? false,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      googlePlaceId: json['google_place_id'],
      sourceDonnees: json['source_donnees'] ?? 'local',
      statutVerification: json['statut_verification'] ?? 'verifiee_officielle',
      sourceVerification: json['source_verification'] ?? 'ONPT Togo',
      dateDerniereSynchro: json['date_derniere_synchro'],
      periodeGarde: json['periode_garde'] != null
          ? PeriodeGardeInfo.fromJson(json['periode_garde'] as Map<String, dynamic>)
          : null,
    );
  }
}

class StockItem {
  final int id;
  final int pharmacieId;
  final String pharmacieNom;
  final String pharmacieVille;
  final String pharmacieAdresse;
  final String pharmacieTelephone;
  final bool pharmacieEstDeGarde;
  final int medicamentId;
  final String medicamentNom;
  final String medicamentFormeDosage;
  final String medicamentDci;
  final bool medicamentEstEssentiel;
  final int quantite;
  final bool estDisponible;
  final double prix;

  StockItem({
    required this.id,
    required this.pharmacieId,
    required this.pharmacieNom,
    required this.pharmacieVille,
    required this.pharmacieAdresse,
    required this.pharmacieTelephone,
    required this.pharmacieEstDeGarde,
    required this.medicamentId,
    required this.medicamentNom,
    required this.medicamentFormeDosage,
    required this.medicamentDci,
    required this.medicamentEstEssentiel,
    required this.quantite,
    required this.estDisponible,
    required this.prix,
  });

  factory StockItem.fromJson(Map<String, dynamic> json) {
    return StockItem(
      id: json['id'] ?? 0,
      pharmacieId: json['pharmacie'] ?? 0,
      pharmacieNom: json['pharmacie_nom'] ?? '',
      pharmacieVille: json['pharmacie_ville'] ?? '',
      pharmacieAdresse: json['pharmacie_adresse'] ?? '',
      pharmacieTelephone: json['pharmacie_telephone'] ?? '',
      pharmacieEstDeGarde: json['pharmacie_est_de_garde'] ?? false,
      medicamentId: json['medicament'] ?? 0,
      medicamentNom: json['medicament_nom'] ?? '',
      medicamentFormeDosage: json['medicament_forme_dosage'] ?? '',
      medicamentDci: json['medicament_dci'] ?? '',
      medicamentEstEssentiel: json['medicament_est_essentiel'] ?? false,
      quantite: json['quantite'] ?? 0,
      estDisponible: json['est_disponible'] ?? true,
      prix: double.tryParse(json['prix']?.toString() ?? '0') ?? 0.0,
    );
  }
}

class PharmacieService {
  final http.Client _client;

  PharmacieService({http.Client? client}) : _client = client ?? http.Client();

  Uri _endpoint(String path, [Map<String, String>? queryParams]) {
    final base = Uri.parse('${ApiConfig.baseUrl}/$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      return base.replace(queryParameters: queryParams);
    }
    return base;
  }

  Future<http.Response> _get(String path, [Map<String, String>? queryParams]) async {
    try {
      final res = await _client.get(_endpoint(path, queryParams)).timeout(const Duration(seconds: 3));
      ApiConfig.markSuccess(ApiConfig.baseUrl);
      return res;
    } catch (_) {
      final wifiUri = Uri.parse('${ApiConfig.wifiBaseUrl}/$path');
      final target = (queryParams != null && queryParams.isNotEmpty)
          ? wifiUri.replace(queryParameters: queryParams)
          : wifiUri;
      final res = await _client.get(target).timeout(const Duration(seconds: 6));
      ApiConfig.markSuccess(ApiConfig.wifiBaseUrl);
      return res;
    }
  }

  Future<http.Response> _post(String path, [Map<String, dynamic>? body]) async {
    final jsonStr = body != null ? jsonEncode(body) : null;
    final headers = {'Content-Type': 'application/json'};
    try {
      final res = await _client.post(_endpoint(path), headers: headers, body: jsonStr).timeout(const Duration(seconds: 3));
      ApiConfig.markSuccess(ApiConfig.baseUrl);
      return res;
    } catch (_) {
      final wifiUri = Uri.parse('${ApiConfig.wifiBaseUrl}/$path');
      final res = await _client.post(wifiUri, headers: headers, body: jsonStr).timeout(const Duration(seconds: 6));
      ApiConfig.markSuccess(ApiConfig.wifiBaseUrl);
      return res;
    }
  }

  /// Récupère la liste des pharmacies (filtrage par garde, ville, zone, recherche, proximité GPS)
  Future<List<PharmacieItem>> getPharmacies({
    bool? deGarde,
    String? ville,
    String? zone,
    String? recherche,
    double? lat,
    double? lng,
  }) async {
    final params = <String, String>{};
    if (deGarde != null) {
      params['est_de_garde'] = deGarde ? 'true' : 'false';
    }
    if (ville != null && ville.trim().isNotEmpty) {
      params['ville'] = ville.trim();
    }
    if (zone != null && zone.trim().isNotEmpty) {
      params['zone'] = zone.trim();
    }
    if (recherche != null && recherche.trim().isNotEmpty) {
      params['recherche'] = recherche.trim();
    }
    if (lat != null) {
      params['lat'] = lat.toString();
    }
    if (lng != null) {
      params['lng'] = lng.toString();
    }

    final response = await _get('pharmacies/', params);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((e) => PharmacieItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Erreur lors du chargement des pharmacies (${response.statusCode})');
  }

  /// Recherche dynamique connectée à Google Places API avec mise en cache et statut ONPT
  Future<Map<String, dynamic>> rechercheDynamique({
    String? query,
    String? ville,
    double? lat,
    double? lng,
    int? rayon,
    bool refresh = false,
  }) async {
    final params = <String, String>{};
    if (query != null && query.trim().isNotEmpty) params['recherche'] = query.trim();
    if (ville != null && ville.trim().isNotEmpty) params['ville'] = ville.trim();
    if (lat != null) params['lat'] = lat.toString();
    if (lng != null) params['lng'] = lng.toString();
    if (rayon != null) params['rayon'] = rayon.toString();
    if (refresh) params['refresh'] = 'true';

    final response = await _get('pharmacies/recherche-dynamique/', params);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      final rawList = data['resultats'] as List<dynamic>? ?? [];
      final List<PharmacieItem> items = rawList
          .map((e) => PharmacieItem.fromJson(e as Map<String, dynamic>))
          .toList();

      return {
        'source': data['source'] ?? 'local',
        'message': data['message'] ?? '',
        'derniere_mise_a_jour': data['derniere_mise_a_jour'],
        'total': data['total'] ?? items.length,
        'resultats': items,
      };
    }
    throw Exception('Erreur lors de la recherche dynamique (${response.statusCode})');
  }

  /// Récupère les statistiques nationales de couverture des gardes
  Future<Map<String, dynamic>> getStatistiquesGardes() async {
    final response = await _get('pharmacies/gardes/statistiques/');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('Erreur lors du chargement des statistiques (${response.statusCode})');
  }

  /// Déclenche un recalcul immédiat des gardes
  Future<Map<String, dynamic>> actualiserGardes() async {
    final response = await _post('pharmacies/gardes/actualiser/');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('Erreur lors de l’actualisation des gardes (${response.statusCode})');
  }

  /// Recherche les médicaments et leurs stocks en temps réel
  Future<List<StockItem>> searchStocks({String? query, String? ville}) async {
    final params = <String, String>{};
    if (query != null && query.trim().isNotEmpty) {
      params['recherche'] = query.trim();
    }
    if (ville != null && ville.trim().isNotEmpty) {
      params['ville'] = ville.trim();
    }

    final response = await _get('stocks/', params);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((e) => StockItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Erreur lors de la recherche des médicaments (${response.statusCode})');
  }
}
