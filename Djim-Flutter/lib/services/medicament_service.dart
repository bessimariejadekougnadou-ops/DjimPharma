import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'pharmacie_service.dart';

class MedicamentItem {
  final int id;
  final String nom;
  final String dci;
  final String dosage;
  final String formePharmaceutique;
  final String presentation;
  final String laboratoireFabricant;
  final String categorieTherapeutique;
  final String niveauxSoins;
  final String statutReglementaire;
  final String statutReglementaireDisplay;
  final String sourceInformation;
  final String identifiantExterne;
  final bool estEssentiel;
  final bool necessiteValidationManuelle;
  final String description;
  final String disponibiliteStatut;
  final String disponibiliteLibelle;
  final String disponibiliteMessage;
  final bool peutContacterPharmacie;
  final int? prixMin;
  final int? prixMax;
  final String? prixIndicatif;
  final int nombrePharmaciesDisponibles;
  final List<PharmacieStockItem> pharmaciesDisponibles;

  MedicamentItem({
    required this.id,
    required this.nom,
    required this.dci,
    required this.dosage,
    required this.formePharmaceutique,
    required this.presentation,
    required this.laboratoireFabricant,
    required this.categorieTherapeutique,
    required this.niveauxSoins,
    required this.statutReglementaire,
    required this.statutReglementaireDisplay,
    required this.sourceInformation,
    required this.identifiantExterne,
    required this.estEssentiel,
    required this.necessiteValidationManuelle,
    required this.description,
    required this.disponibiliteStatut,
    required this.disponibiliteLibelle,
    required this.disponibiliteMessage,
    required this.peutContacterPharmacie,
    this.prixMin,
    this.prixMax,
    this.prixIndicatif,
    this.nombrePharmaciesDisponibles = 0,
    this.pharmaciesDisponibles = const [],
  });

  factory MedicamentItem.fromJson(Map<String, dynamic> json) {
    return MedicamentItem(
      id: json['id'] ?? 0,
      nom: json['nom'] ?? '',
      dci: json['dci'] ?? '',
      dosage: json['dosage'] ?? '',
      formePharmaceutique: json['forme_pharmaceutique'] ?? '',
      presentation: json['presentation'] ?? '',
      laboratoireFabricant: json['laboratoire_fabricant'] ?? '',
      categorieTherapeutique: json['categorie_therapeutique'] ?? '',
      niveauxSoins: json['niveaux_soins'] ?? '',
      statutReglementaire: json['statut_reglementaire'] ?? 'liste_essentielle_togo',
      statutReglementaireDisplay: json['statut_reglementaire_display'] ?? 'Liste Nationale des Médicaments Essentiels (Togo)',
      sourceInformation: json['source_information'] ?? 'Arrêté N° 147/2021/MSHPAUS - LNME Togo',
      identifiantExterne: json['identifiant_externe'] ?? '',
      estEssentiel: json['est_essentiel'] ?? true,
      necessiteValidationManuelle: json['necessite_validation_manuelle'] ?? false,
      description: json['description'] ?? '',
      disponibiliteStatut: json['disponibilite_statut'] ?? 'non_confirmee',
      disponibiliteLibelle: json['disponibilite_libelle'] ?? 'Disponibilité non confirmée',
      disponibiliteMessage: json['disponibilite_message'] ?? 'Aucun stock en temps réel n\'est synchronisé pour ce médicament. Veuillez contacter directement une pharmacie.',
      peutContacterPharmacie: json['peut_contacter_pharmacie'] ?? true,
      prixMin: (json['prix_min'] as num?)?.toInt(),
      prixMax: (json['prix_max'] as num?)?.toInt(),
      prixIndicatif: json['prix_indicatif'],
      nombrePharmaciesDisponibles: (json['nombre_pharmacies_disponibles'] as num?)?.toInt() ?? 0,
      pharmaciesDisponibles: ((json['pharmacies_disponibles'] as List?) ?? [])
          .map((e) => PharmacieStockItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PharmacieStockItem {
  final int pharmacieId;
  final String nom;
  final String adresse;
  final String ville;
  final String quartier;
  final String telephone;
  final bool estDeGarde;
  final double? latitude;
  final double? longitude;
  final int prix;
  final int quantite;
  final String statutStock;
  final String codeExterne;

  PharmacieStockItem({
    required this.pharmacieId,
    required this.nom,
    required this.adresse,
    required this.ville,
    required this.quartier,
    required this.telephone,
    required this.estDeGarde,
    this.latitude,
    this.longitude,
    required this.prix,
    required this.quantite,
    required this.statutStock,
    required this.codeExterne,
  });

  factory PharmacieStockItem.fromJson(Map<String, dynamic> json) {
    return PharmacieStockItem(
      pharmacieId: json['pharmacie_id'] ?? 0,
      nom: json['nom'] ?? '',
      adresse: json['adresse'] ?? '',
      ville: json['ville'] ?? '',
      quartier: json['quartier'] ?? '',
      telephone: json['telephone'] ?? '',
      estDeGarde: json['est_de_garde'] ?? false,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      prix: (json['prix'] as num?)?.toInt() ?? 0,
      quantite: (json['quantite'] as num?)?.toInt() ?? 0,
      statutStock: json['statut_stock'] ?? 'DISPONIBLE',
      codeExterne: json['code_externe'] ?? '',
    );
  }
}

class MedicamentService {
  final http.Client _client;

  MedicamentService({http.Client? client}) : _client = client ?? http.Client();

  Future<http.Response> _get(String path, [Map<String, String>? queryParams]) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/$path');
      final target = (queryParams != null && queryParams.isNotEmpty)
          ? uri.replace(queryParameters: queryParams)
          : uri;
      final res = await _client.get(target).timeout(const Duration(seconds: 4));
      ApiConfig.markSuccess(ApiConfig.baseUrl);
      return res;
    } catch (_) {
      final wifiUri = Uri.parse('${ApiConfig.wifiBaseUrl}/$path');
      final target = (queryParams != null && queryParams.isNotEmpty)
          ? wifiUri.replace(queryParameters: queryParams)
          : wifiUri;
      final res = await _client.get(target).timeout(const Duration(seconds: 8));
      ApiConfig.markSuccess(ApiConfig.wifiBaseUrl);
      return res;
    }
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final encoded = jsonEncode(body);
    try {
      final res = await _client.post(
        Uri.parse('${ApiConfig.baseUrl}/$path'),
        headers: {'Content-Type': 'application/json'},
        body: encoded,
      ).timeout(const Duration(seconds: 4));
      ApiConfig.markSuccess(ApiConfig.baseUrl);
      return res;
    } catch (_) {
      final res = await _client.post(
        Uri.parse('${ApiConfig.wifiBaseUrl}/$path'),
        headers: {'Content-Type': 'application/json'},
        body: encoded,
      ).timeout(const Duration(seconds: 8));
      ApiConfig.markSuccess(ApiConfig.wifiBaseUrl);
      return res;
    }
  }

  /// Recherche dans le catalogue officiel des médicaments (insensible aux accents et majuscules)
  Future<Map<String, dynamic>> chercherMedicaments({
    String query = '',
    int page = 1,
    String categorie = '',
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
      };
      if (query.trim().isNotEmpty) {
        params['q'] = query.trim();
      }
      if (categorie.trim().isNotEmpty) {
        params['categorie'] = categorie.trim();
      }

      final resp = await _get('medicaments/', params);

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final count = (data['count'] as num?)?.toInt() ?? 0;
        final rawList = (data['results'] as List?) ?? [];
        final items = rawList.map((e) => MedicamentItem.fromJson(e as Map<String, dynamic>)).toList();

        return {
          'count': count,
          'results': items,
          'next': data['next'],
          'previous': data['previous'],
        };
      }
    } catch (_) {}

    return {
      'count': 0,
      'results': <MedicamentItem>[],
      'next': null,
      'previous': null,
    };
  }

  /// Récupère la fiche détaillée d'un médicament avec des pharmacies de contact recommandées
  Future<Map<String, dynamic>?> getDetailMedicament(int id) async {
    try {
      final resp = await _get('medicaments/$id/');

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final medicament = MedicamentItem.fromJson(data);

        final rawPharma = (data['pharmacies_contact_recommandees'] as List?) ?? [];
        final pharmacies = rawPharma.map((e) => PharmacieItem.fromJson(e as Map<String, dynamic>)).toList();

        return {
          'medicament': medicament,
          'pharmacies': pharmacies,
        };
      }
    } catch (_) {}
    return null;
  }

  /// Récupère la liste des catégories thérapeutiques du catalogue
  Future<List<String>> getCategories() async {
    try {
      final resp = await _get('medicaments/categories/');

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final cats = (data['categories'] as List?) ?? [];
        return cats.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Envoie une demande de vérification de disponibilité à une pharmacie
  Future<bool> envoyerDemandeDisponibilite({
    required int medicamentId,
    required int pharmacieId,
    required String nomPatient,
    required String telephonePatient,
    String message = '',
  }) async {
    try {
      final resp = await _post('medicaments/demandes-disponibilite/', {
        'medicament': medicamentId,
        'pharmacie': pharmacieId,
        'nom_patient': nomPatient,
        'telephone_patient': telephonePatient,
        'message': message,
      });

      return resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
