import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pharmacie_service.dart';

class PharmacieMapScreen extends StatefulWidget {
  final bool initialGardeOnly;
  const PharmacieMapScreen({super.key, this.initialGardeOnly = false});

  @override
  State<PharmacieMapScreen> createState() => _PharmacieMapScreenState();
}

class _PharmacieMapScreenState extends State<PharmacieMapScreen> {
  static const _platform = MethodChannel('com.example.djim_flutter/map_launcher');
  final PharmacieService _pharmacieService = PharmacieService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  bool _onlyGarde = false;
  String _selectedCity = 'Toutes';
  String _sourceInfo = 'Données officielles ONPT Togo';
  String? _derniereMiseAJour;

  List<PharmacieItem> _pharmacies = [];
  List<PharmacieItem> _toutesPharmacies = [];
  Timer? _debounceTimer;
  Map<String, dynamic>? _statsGardes;
  PharmacieItem? _selectedPharmacie;

  // Position actuelle de l'utilisateur (par défaut position GPS réelle)
  String _myLocationName = "Position GPS Réelle 📍";
  double _myLat = 6.1365;
  double _myLng = 1.2185;
  bool _isGpsReel = false;

  final List<Map<String, dynamic>> _positionsTogo = [
    {"nom": "Ma Position GPS Réelle 📍", "lat": 6.1365, "lng": 1.2185},
    {"nom": "Lomé (Tokoin / Centre)", "lat": 6.1365, "lng": 1.2185},
    {"nom": "Lomé (Assivito / Grand Marché)", "lat": 6.1250, "lng": 1.2220},
    {"nom": "Lomé (Agoè-Nyivé)", "lat": 6.2100, "lng": 1.2050},
    {"nom": "Lomé (Bè / Adidogomé)", "lat": 6.1473, "lng": 1.2489},
    {"nom": "Lomé (Baguida / Port)", "lat": 6.1550, "lng": 1.3200},
    {"nom": "Lomé (Aéroport / Klikamé)", "lat": 6.1689, "lng": 1.2458},
    {"nom": "Kara (Centre Ville)", "lat": 9.5511, "lng": 1.1861},
    {"nom": "Sokodé (Grand Marché)", "lat": 8.9833, "lng": 1.1333},
    {"nom": "Kpalimé (Gare)", "lat": 6.9000, "lng": 0.6333},
  ];

  final List<String> _villesTogo = [
    'Toutes',
    'Lomé',
    'Kara',
    'Sokodé',
    'Kpalimé',
    'Atakpamé',
  ];

  @override
  void initState() {
    super.initState();
    _onlyGarde = widget.initialGardeOnly;
    _detecterPositionGpsReelle();
  }

  Future<void> _detecterPositionGpsReelle() async {
    try {
      final res = await _platform.invokeMethod('getCurrentLocation');
      if (res != null && res is Map) {
        final double? lat = res['lat'] != null ? (res['lat'] as num).toDouble() : null;
        final double? lng = res['lng'] != null ? (res['lng'] as num).toDouble() : null;
        if (lat != null && lng != null && mounted) {
          setState(() {
            _myLat = lat;
            _myLng = lng;
            _isGpsReel = true;
            _myLocationName = "Lomé • Position GPS vérifiée";
            _positionsTogo[0] = {
              "nom": "Lomé • Position GPS vérifiée",
              "lat": lat,
              "lng": lng,
            };
          });
          await _loadData();
          return;
        }
      }

      await _platform.invokeMethod('requestLocationPermission');
      await Future.delayed(const Duration(milliseconds: 1200));
      final retry = await _platform.invokeMethod('getCurrentLocation');
      if (retry != null && retry is Map && mounted) {
        final double? lat = retry['lat'] != null ? (retry['lat'] as num).toDouble() : null;
        final double? lng = retry['lng'] != null ? (retry['lng'] as num).toDouble() : null;
        if (lat != null && lng != null) {
          setState(() {
            _myLat = lat;
            _myLng = lng;
            _isGpsReel = true;
            _myLocationName = "Lomé • Position GPS vérifiée";
          });
          await _loadData();
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      await _loadData();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Normalisation tolérante aux accents, majuscules et caractères spéciaux
  String _normaliserTexte(String text) {
    var s = text.toLowerCase();
    const withAccents = 'àáâãäåèéêëìíîïòóôõöùúûüýÿçñ';
    const withoutAccents = 'aaaaaaeeeeiiiiooooouuuuyycn';
    for (int i = 0; i < withAccents.length; i++) {
      s = s.replaceAll(withAccents[i], withoutAccents[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9]'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Filtre et trie instantanément les pharmacies avec détection d'intention (garde, proximité, mots-clés)
  List<PharmacieItem> _filtrerEtTrierPharmacies(String query, List<PharmacieItem> source) {
    final qNorm = _normaliserTexte(query);
    if (qNorm.isEmpty) return List.from(source);

    final rawTokens = qNorm.split(' ');
    const stopwords = {
      'de', 'du', 'des', 'la', 'le', 'les', 'a', 'au', 'aux', 'en', 'pour',
      'mon', 'ma', 'mes', 'chez', 'moi', 'd', 'l', 'un', 'une'
    };
    const genericWords = {
      'pharmacie', 'pharmacies', 'officine', 'officines', 'pharma', 'boite', 'dispensaire'
    };
    const gardeWords = {
      'garde', 'gardes', 'nuit', '24h', 'urgence', 'urgences'
    };
    const procheWords = {
      'proche', 'proches', 'pres', 'autour', 'ici', 'voisin', 'voisine'
    };

    final isGardeIntent = rawTokens.any((w) => gardeWords.contains(w));
    final meaningfulTokens = rawTokens.where((w) =>
        !stopwords.contains(w) &&
        !genericWords.contains(w) &&
        !gardeWords.contains(w) &&
        !procheWords.contains(w)).toList();

    List<PharmacieItem> baseList = List.from(source);
    if (isGardeIntent || _onlyGarde) {
      final gardes = baseList.where((p) => p.estDeGarde).toList();
      if (gardes.isNotEmpty) baseList = gardes;
    }

    if (meaningfulTokens.isEmpty) {
      baseList.sort((a, b) {
        final dA = _calculerDistanceKm(a.latitude, a.longitude);
        final dB = _calculerDistanceKm(b.latitude, b.longitude);
        return dA.compareTo(dB);
      });
      return baseList;
    }

    final scored = <MapEntry<int, PharmacieItem>>[];

    for (final p in baseList) {
      final nomNorm = _normaliserTexte(p.nom);
      final nomWords = nomNorm.split(' ').where((w) => !genericWords.contains(w) && !stopwords.contains(w)).toList();
      final quartierWords = _normaliserTexte(p.quartier).split(' ');
      final addrWords = _normaliserTexte("${p.adresse} ${p.ville}").split(' ');
      final haystack = _normaliserTexte("${p.nom} ${p.adresse} ${p.quartier} ${p.ville}");

      if (!meaningfulTokens.any((t) => haystack.contains(t))) continue;

      int score = 5;
      if (meaningfulTokens.any((t) => nomWords.any((w) => w.startsWith(t)))) {
        score = 1;
      } else if (meaningfulTokens.any((t) => nomNorm.contains(t))) {
        score = 2;
      } else if (meaningfulTokens.any((t) => quartierWords.any((w) => w.startsWith(t)))) {
        score = 3;
      } else if (meaningfulTokens.any((t) => addrWords.any((w) => w.startsWith(t)))) {
        score = 4;
      }

      scored.add(MapEntry(score, p));
    }

    scored.sort((a, b) {
      if (a.key != b.key) return a.key.compareTo(b.key);
      final distA = _calculerDistanceKm(a.value.latitude, a.value.longitude);
      final distB = _calculerDistanceKm(b.value.latitude, b.value.longitude);
      return distA.compareTo(distB);
    });

    return scored.map((e) => e.value).toList();
  }

  /// Ouvre directement Google Maps (application ou https://maps.google.com/) centré sur les pharmacies
  Future<void> _ouvrirGoogleMapsDirect([String? motCle]) async {
    try {
      await _platform.invokeMethod('launchMaps', {
        'destLat': _myLat,
        'destLng': _myLng,
        'label': (motCle != null && motCle.isNotEmpty) ? motCle : 'Pharmacies',
        'mode': 'search',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Ouverture de Google Maps (maps.google.com) pour \"${motCle ?? 'Pharmacies'}\"...",
            ),
            backgroundColor: const Color(0xFF047857),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      final url = "https://www.google.com/maps/search/pharmacies/@$_myLat,$_myLng,15z";
      if (mounted) {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Lien Google Maps copié dans le presse-papier !"),
            backgroundColor: Color(0xFF047857),
          ),
        );
      }
    }
  }

  /// Recherche dynamique instantanée lettre par lettre (0ms) + enrichissement serveur debouncé
  void _onSearchChanged(String val) {
    final query = val.trim();
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _pharmacies = _onlyGarde
            ? _toutesPharmacies.where((p) => p.estDeGarde).toList()
            : List.from(_toutesPharmacies);
      });
      return;
    }

    // 1. Filtrage instantané (0ms) en mémoire locale
    final base = _onlyGarde
        ? _toutesPharmacies.where((p) => p.estDeGarde).toList()
        : _toutesPharmacies;
    final instantMatches = _filtrerEtTrierPharmacies(query, base);
    setState(() {
      _pharmacies = instantMatches;
    });

    // 2. Appel serveur en arrière-plan debouncé (180ms)
    _debounceTimer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final res = await _pharmacieService.rechercheDynamique(
          query: query,
          ville: _selectedCity == 'Toutes' ? null : _selectedCity,
          lat: _myLat,
          lng: _myLng,
        );
        final List<PharmacieItem> items = (res['resultats'] as List<PharmacieItem>?) ?? [];
        if (items.isNotEmpty && mounted) {
          final filtres = _onlyGarde ? items.where((p) => p.estDeGarde).toList() : items;
          final tries = _filtrerEtTrierPharmacies(query, filtres);
          setState(() {
            _pharmacies = tries.isNotEmpty ? tries : filtres;
            _sourceInfo = res['message'] ?? 'Recherche dynamique';
          });
        }
      } catch (_) {}
    });
  }

  /// Calcule la distance orthodromique réelle en kilomètres
  double _calculerDistanceKm(double? lat, double? lng) {
    if (lat == null || lng == null) return 9999.0;
    final dLat = (lat - _myLat) * 111.0;
    final dLng = (lng - _myLng) * 111.0 * cos(_myLat * pi / 180.0);
    return sqrt(dLat * dLat + dLng * dLng);
  }

  /// Formate la distance de manière conviviale
  String _formatDistance(double distKm) {
    if (distKm >= 9000) return "Distance non définie";
    if (distKm < 1.0) {
      final metres = (distKm * 1000).toInt();
      return "$metres m";
    }
    return "${distKm.toStringAsFixed(1)} km";
  }

  /// Estime le temps de trajet en voiture / moto
  String _estimerDureeVoiture(double distKm) {
    if (distKm >= 9000) return "~5 min";
    final minutes = max(2, (distKm / 30.0 * 60).round());
    return "~$minutes min";
  }

  /// Estime le temps de trajet à pied
  String _estimerDureePied(double distKm) {
    if (distKm >= 9000) return "~15 min";
    final minutes = max(5, (distKm / 4.5 * 60).round());
    return "~$minutes min";
  }

  /// Charge et TRIE IMPÉRATIVEMENT les pharmacies par proximité croissante
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final futures = await Future.wait([
        _pharmacieService.getPharmacies(
          deGarde: _onlyGarde ? true : null,
          ville: _selectedCity == 'Toutes' ? null : _selectedCity,
          recherche: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
          lat: _myLat,
          lng: _myLng,
        ),
        _pharmacieService.getStatistiquesGardes().catchError((_) => <String, dynamic>{}),
      ]);

      final pharms = futures[0] as List<PharmacieItem>;
      final stats = futures[1] as Map<String, dynamic>;

      // ── TRI OBLIGATOIRE PAR PROXIMITÉ (LES PLUS PROCHES D'ABORD) ──
      pharms.sort((a, b) {
        final distA = _calculerDistanceKm(a.latitude, a.longitude);
        final distB = _calculerDistanceKm(b.latitude, b.longitude);
        return distA.compareTo(distB);
      });

      if (!mounted) return;
      setState(() {
        _toutesPharmacies = List.from(pharms);
        _pharmacies = pharms;
        _statsGardes = stats;
        _derniereMiseAJour = DateTime.now().toLocal().toString().substring(11, 16);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible de contacter le serveur backend.\nVérifiez la connexion réseau.';
        _isLoading = false;
      });
    }
  }

  Future<void> _rechercheDynamique() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _loadData();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await _pharmacieService.rechercheDynamique(
        query: query,
        ville: _selectedCity == 'Toutes' ? null : _selectedCity,
        lat: _myLat,
        lng: _myLng,
      );

      final List<PharmacieItem> items = res['resultats'] as List<PharmacieItem>;

      // Tri des résultats par proximité
      items.sort((a, b) {
        final distA = _calculerDistanceKm(a.latitude, a.longitude);
        final distB = _calculerDistanceKm(b.latitude, b.longitude);
        return distA.compareTo(distB);
      });

      if (!mounted) return;
      setState(() {
        _pharmacies = _onlyGarde ? items.where((p) => p.estDeGarde).toList() : items;
        _sourceInfo = res['message'] ?? 'Recherche dynamique';
        _isLoading = false;
      });
    } catch (_) {
      _loadData();
    }
  }

  Future<void> _actualiserGardesServeur() async {
    setState(() => _isRefreshing = true);
    try {
      final res = await _pharmacieService.actualiserGardes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Recalcul terminé : ${res['total_gardes_actives'] ?? 0} pharmacies de garde confirmées.",
          ),
          backgroundColor: const Color(0xFF047857),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadData();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Échec du rafraîchissement avec le serveur."),
            backgroundColor: Color(0xFFB42318),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  /// Ouvre directement Google Maps (Navigation ou Repère) vers la Pharmacie
  Future<void> _lancerGoogleMaps(PharmacieItem p, {String mode = 'navigation'}) async {
    final destLat = p.latitude ?? _myLat;
    final destLng = p.longitude ?? _myLng;

    try {
      await _platform.invokeMethod('launchMaps', {
        'destLat': destLat,
        'destLng': destLng,
        'label': p.nom,
        'mode': mode,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mode == 'navigation'
                  ? "Google Maps : Calcul de l'itinéraire vers ${p.nom}..."
                  : "Google Maps : Affichage de l'emplacement de ${p.nom}...",
            ),
            backgroundColor: const Color(0xFF047857),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      final url = "https://www.google.com/maps/search/?api=1&query=$destLat,$destLng";
      if (mounted) {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Lien Google Maps copié dans le presse-papier !"),
            backgroundColor: Color(0xFF047857),
          ),
        );
      }
    }
  }

  /// Lance un appel téléphonique direct vers la pharmacie via le Intent Android natif
  Future<void> _lancerAppel(String telephone) async {
    final clean = telephone.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Numéro de téléphone non disponible pour cette pharmacie"),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
      return;
    }

    try {
      await _platform.invokeMethod('makePhoneCall', {'phoneNumber': clean, 'phone': clean});
    } catch (_) {
      if (mounted) {
        Clipboard.setData(ClipboardData(text: clean));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Numéro $clean copié dans le presse-papier !"),
            backgroundColor: const Color(0xFF047857),
          ),
        );
      }
    }
  }

  /// AFFICHE LE PANNEAU INFÉRIEUR (BOTTOM SHEET) GOOGLE MAPS ITINÉRAIRE
  void _showItineraireBottomSheet(PharmacieItem p) {
    setState(() => _selectedPharmacie = p);
    final dist = _calculerDistanceKm(p.latitude, p.longitude);
    final distTexte = _formatDistance(dist);
    final dureeVoiture = _estimerDureeVoiture(dist);
    final dureePied = _estimerDureePied(dist);
    final isGarde = p.estDeGarde;
    final periode = p.periodeGarde;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poignée de glissement
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // En-tête
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF047857).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.directions_rounded, color: Color(0xFF047857), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Itinéraire Google Maps",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                          ),
                          Text(
                            "Localisation en direct Togo 🇹🇬",
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isGarde)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF047857),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        "DE GARDE 🛡️",
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),

              // ── VISUALISATION DU TRAJET ÉTAPE PAR ÉTAPE (DÉPART -> ARRIVÉE) ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    // Étape 1 : Mon lieu actuel (DÉPART)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF10B981),
                              ),
                              child: const Center(
                                child: Icon(Icons.my_location_rounded, size: 12, color: Colors.white),
                              ),
                            ),
                            Container(
                              width: 2,
                              height: 42,
                              color: const Color(0xFFCBD5E1),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Mon lieu actuel (Point de départ)",
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _myLocationName,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                              ),
                              Text(
                                "GPS: ${_myLat.toStringAsFixed(4)}, ${_myLng.toStringAsFixed(4)}",
                                style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Infos intermédiaire trajet (Distance & Temps)
                    Padding(
                      padding: const EdgeInsets.only(left: 32, bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6FDF4),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.navigation_rounded, size: 12, color: Color(0xFF047857)),
                                const SizedBox(width: 4),
                                Text(
                                  distTexte,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF047857)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "🚗 $dureeVoiture  •  🚶 $dureePied",
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                          ),
                        ],
                      ),
                    ),

                    // Étape 2 : Destination (PHARMACIE SÉLECTIONNÉE)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isGarde ? const Color(0xFF047857) : const Color(0xFFEF4444),
                          ),
                          child: const Center(
                            child: Icon(Icons.place_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isGarde ? "Destination • Pharmacie de Garde 🛡️" : "Destination • Pharmacie",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isGarde ? const Color(0xFF047857) : const Color(0xFFEF4444),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.nom,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                              ),
                              Text(
                                "${p.adresse} • ${p.ville}",
                                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                              ),
                              if (p.telephone.isNotEmpty)
                                Text(
                                  "📞 Contact : ${p.telephone}",
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.w700),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (isGarde && periode != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF047857)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Période officielle validée par l'ONPT Togo • Secteur : ${periode.zone}",
                          style: const TextStyle(fontSize: 11, color: Color(0xFF166534), fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 22),

              // BOUTONS GOOGLE MAPS (NAVIGATION & EMPLACEMENT)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _lancerGoogleMaps(p, mode: 'navigation');
                  },
                  icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
                  label: const Text(
                    "Démarrer l'itinéraire GPS",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF047857),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Bouton 2 : Voir l'emplacement précis sur la carte
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _lancerGoogleMaps(p, mode: 'view');
                  },
                  icon: const Icon(Icons.place_rounded, color: Color(0xFF047857), size: 20),
                  label: const Text(
                    "Voir l'emplacement sur Google Maps",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF047857)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF047857), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),

              if (p.telephone.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _lancerAppel(p.telephone);
                    },
                    icon: const Icon(Icons.phone_rounded, color: Colors.white, size: 20),
                    label: Text(
                      "Appeler la pharmacie (${p.telephone})",
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Bouton secondaire fermer
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Fermer la vue de trajet", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Sélecteur de quartier ou position actuelle
  void _changerPositionActuelleDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.my_location_rounded, color: Color(0xFF047857)),
                SizedBox(width: 8),
                Text(
                  "Changer mon lieu actuel au Togo",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              "Les pharmacies seront immédiatement re-triées de la plus proche à la plus éloignée.",
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const Divider(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: _positionsTogo.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final pos = _positionsTogo[idx];
                  final isCurrent = pos['nom'] == _myLocationName;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.place_rounded,
                      color: isCurrent ? const Color(0xFF047857) : const Color(0xFF94A3B8),
                    ),
                    title: Text(
                      pos['nom'] as String,
                      style: TextStyle(
                        fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                        color: isCurrent ? const Color(0xFF047857) : const Color(0xFF0F172A),
                      ),
                    ),
                    trailing: isCurrent ? const Icon(Icons.check_circle_rounded, color: Color(0xFF047857)) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _myLocationName = pos['nom'] as String;
                        _myLat = pos['lat'] as double;
                        _myLng = pos['lng'] as double;
                      });
                      _loadData();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FAF7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Pharmacies",
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
            ),
            Text(
              "${_pharmacies.length} officines • Triées par proximité",
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF047857), fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Ma position GPS réelle",
            icon: const Icon(Icons.my_location_rounded, color: Color(0xFF047857), size: 21),
            onPressed: () {
              setState(() {
                _selectedCity = 'Toutes';
                _searchController.clear();
              });
              _detecterPositionGpsReelle();
            },
          ),
          IconButton(
            tooltip: "Actualiser les données",
            icon: _isRefreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF047857)))
                : const Icon(Icons.refresh_rounded, color: Color(0xFF047857), size: 22),
            onPressed: _isRefreshing ? null : _actualiserGardesServeur,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── BANDEAU LIEU ACTUEL & RECHERCHE ────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                // Sélecteur de position actuelle cliquable (Pill moderne & professionnel)
                GestureDetector(
                  onTap: _changerPositionActuelleDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6FDF4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.location_on_rounded, color: Color(0xFF047857), size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "VOTRE POINT DE DÉPART",
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _myLocationName,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6FDF4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Changer",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF047857),
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF047857), size: 16),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Barre de recherche avec filtrage instantané
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    onSubmitted: (_) => _rechercheDynamique(),
                    decoration: InputDecoration(
                      hintText: "Rechercher une pharmacie (nom, quartier)...",
                      hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF047857), size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      isDense: true,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Filtres de Villes (Pills modernes & épurés)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _villesTogo.map((ville) {
                      final isSel = _selectedCity == ville;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedCity = ville);
                            _loadData();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFF047857) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel ? const Color(0xFF047857) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Text(
                              ville,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                color: isSel ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 8),

                // Indicateur de tri & Toggle De Garde
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.near_me_rounded, size: 13, color: Color(0xFF047857)),
                        SizedBox(width: 4),
                        Text(
                          "Triées par proximité GPS",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF047857)),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() => _onlyGarde = !_onlyGarde);
                        _loadData();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: _onlyGarde ? const Color(0xFF047857) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _onlyGarde ? const Color(0xFF047857) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_rounded, size: 13, color: _onlyGarde ? Colors.white : const Color(0xFF047857)),
                            const SizedBox(width: 4),
                            Text(
                              "De garde 24/7",
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: _onlyGarde ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── LISTE DES PHARMACIES (TRIÉES DU PLUS PROCHE AU PLUS ÉLOIGNÉ) ──
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF047857)),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFF94A3B8)),
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadData,
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF047857)),
                                child: const Text("Réessayer", style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _pharmacies.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.local_pharmacy_outlined, size: 48, color: Color(0xFF94A3B8)),
                                  const SizedBox(height: 12),
                                  Text(
                                    _onlyGarde
                                        ? "Aucune pharmacie de garde confirmée dans ce secteur."
                                        : "Aucune pharmacie trouvée pour cette recherche.",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    onPressed: () => _ouvrirGoogleMapsDirect(_searchController.text.trim()),
                                    icon: const Icon(Icons.map_rounded, size: 18),
                                    label: const Text("Rechercher sur Google Maps (maps.google.com) 🗺️"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF047857),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      _onSearchChanged('');
                                    },
                                    child: const Text("Réinitialiser et voir les pharmacies"),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                            itemCount: _pharmacies.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final p = _pharmacies[index];
                              return _buildProximityPharmacyCard(p, index);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  /// Carte individuelle de pharmacie (Design médical raffiné & professionnel)
  Widget _buildProximityPharmacyCard(PharmacieItem p, int rank) {
    final dist = _calculerDistanceKm(p.latitude, p.longitude);
    final distStr = _formatDistance(dist);
    final isGarde = p.estDeGarde;
    final periode = p.periodeGarde;
    final isTopProche = rank == 0 && dist < 5.0;

    return GestureDetector(
      onTap: () => _showItineraireBottomSheet(p),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isGarde ? const Color(0xFF047857).withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
            width: isGarde ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bandeau supérieur : Distance & Statut
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Badge Distance
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.navigation_rounded,
                              size: 11,
                              color: Color(0xFF047857),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              distStr,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isTopProche) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "⚡ Plus proche",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Badge Statut : De Garde ou Ouverte
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: isGarde ? const Color(0xFF047857) : const Color(0xFFE6FDF4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isGarde) ...[
                          const Icon(Icons.shield_rounded, size: 11, color: Colors.white),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          isGarde ? "DE GARDE 24/7" : "OUVERTE",
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            color: isGarde ? Colors.white : const Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Contenu principal (Nom, adresse, téléphone)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isGarde ? const Color(0xFFE6FDF4) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isGarde ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Icon(
                      isGarde ? Icons.shield_rounded : Icons.local_pharmacy_rounded,
                      color: isGarde ? const Color(0xFF047857) : const Color(0xFF64748B),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 12, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                "${p.adresse} • ${p.ville}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (p.telephone.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.phone_rounded, size: 11, color: Color(0xFF047857)),
                              const SizedBox(width: 4),
                              Text(
                                p.telephone,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF047857),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Si de garde, mention officielle ONPT
            if (isGarde && periode != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded, size: 13, color: Color(0xFF047857)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Garde officielle ONPT Togo (${periode.zone})",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF166534)),
                      ),
                    ),
                  ],
                ),
              ),

            // Barre d'action inférieure (Itinéraire GPS & Appel direct)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  // Bouton Itinéraire GPS direct
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: () => _lancerGoogleMaps(p, mode: 'navigation'),
                      icon: const Icon(Icons.navigation_rounded, size: 14, color: Colors.white),
                      label: Text(
                        "Itinéraire (${_estimerDureeVoiture(dist)})",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF047857),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Bouton Appel direct vers composeur
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () => _lancerAppel(p.telephone),
                      icon: const Icon(Icons.phone_rounded, size: 13, color: Color(0xFF047857)),
                      label: const Text(
                        "Appel",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF047857),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF047857), width: 1.1),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
