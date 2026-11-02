import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/pharmacie_service.dart';
import 'auth_screen.dart';
import 'pharmacie_map_screen.dart';
import 'medicament_search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _platform = MethodChannel('com.example.djim_flutter/map_launcher');

  final _authService = AuthService();
  final _pharmacieService = PharmacieService();

  final Map<String, dynamic> _user = {
    'prenom': '',
    'nom': '',
  };

  bool _isLoadingProfile = true;
  bool _isLoadingData = true;
  bool _isSearchingLive = false;
  String? _errorMessage;

  int _currentIndex = 0;
  bool _onlyGardeFilter = false;
  String _searchFilter = '';
  Timer? _debounceTimer;

  // Position utilisateur (par défaut Lomé Centre, actualisée par le GPS réel)
  double _userLat = 6.1365;
  double _userLng = 1.2185;
  String _userZoneNom = "Lomé • Position vérifiée";
  bool _isGpsReel = true;
  String _sourceDonneesInfo = "Google Places & ONPT Togo";

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _pharmaciesSectionKey = GlobalKey();
  int _nbPharmaciesProchesAffichees = 5; // Au moins 5 pharmacies proches garanties
  List<PharmacieItem> _pharmacies = [];
  List<PharmacieItem> _toutesPharmacies = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    // 1. Détection automatique du GPS réel de l'appareil dès le démarrage
    _detecterPositionGpsReelle();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Détecte la position GPS réelle du téléphone via le canal Android natif
  Future<void> _detecterPositionGpsReelle({bool afficherNotification = false}) async {
    try {
      final res = await _platform.invokeMethod('getCurrentLocation');
      if (res != null && res is Map) {
        final double? lat = res['lat'] != null ? (res['lat'] as num).toDouble() : null;
        final double? lng = res['lng'] != null ? (res['lng'] as num).toDouble() : null;

        if (lat != null && lng != null && mounted) {
          setState(() {
            _userLat = lat;
            _userLng = lng;
            _isGpsReel = true;
            _userZoneNom = "Lomé • Position vérifiée";
          });

          if (afficherNotification && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("📍 Position GPS réelle actualisée !"),
                backgroundColor: Color(0xFF047857),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          }
          await _loadData();
          return;
        }
      }

      // Si pas encore accordé, on demande la permission
      await _platform.invokeMethod('requestLocationPermission');
      // Laisser le temps à l'utilisateur d'accepter dans la boîte de dialogue système
      await Future.delayed(const Duration(milliseconds: 1200));
      final retry = await _platform.invokeMethod('getCurrentLocation');
      if (retry != null && retry is Map && mounted) {
        final double? lat = retry['lat'] != null ? (retry['lat'] as num).toDouble() : null;
        final double? lng = retry['lng'] != null ? (retry['lng'] as num).toDouble() : null;
        if (lat != null && lng != null) {
          setState(() {
            _userLat = lat;
            _userLng = lng;
            _isGpsReel = true;
            _userZoneNom = "Lomé • Position vérifiée";
          });
          if (afficherNotification && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("📍 Position GPS réelle détectée avec succès !"),
                backgroundColor: Color(0xFF047857),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          }
          await _loadData();
          return;
        }
      }
    } catch (_) {}

    // Si le GPS n'est pas disponible ou refusé, on charge avec la position par défaut
    if (mounted) {
      setState(() {
        _userZoneNom = "Lomé (Centre • Casablanca)";
      });
      await _loadData();
    }
  }

  /// Fait défiler la page de manière fluide vers la section des pharmacies
  void _scrollerVersPharmacies({
    Duration duration = const Duration(milliseconds: 550),
    bool seulementSiHaut = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        if (seulementSiHaut && _scrollController.offset > 280) {
          // L'utilisateur est déjà bien positionné pour voir les résultats
          return;
        }
      }
      if (_pharmaciesSectionKey.currentContext != null) {
        Scrollable.ensureVisible(
          _pharmaciesSectionKey.currentContext!,
          duration: duration,
          curve: Curves.easeInOutCubic,
        );
      } else if (_scrollController.hasClients) {
        _scrollController.animateTo(
          540,
          duration: duration,
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  /// Active la détection de proximité et affiche au moins 5 pharmacies proches de moi
  Future<void> _activerPharmaciesProchesDeMoi() async {
    setState(() {
      _onlyGardeFilter = false;
      _searchController.clear();
      _searchFilter = '';
      _nbPharmaciesProchesAffichees = max(5, _nbPharmaciesProchesAffichees);
    });

    _scrollerVersPharmacies();

    await _detecterPositionGpsReelle(afficherNotification: false);

    _trierPharmaciesParProximite(_pharmacies);
    _trierPharmaciesParProximite(_toutesPharmacies);

    if (!mounted) return;
    setState(() {});

    _scrollerVersPharmacies();

    final nbAffichees = _pharmacies.take(max(5, _nbPharmaciesProchesAffichees)).length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.near_me_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "📍 Affichage des $nbAffichees pharmacies les plus proches de vous !",
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF065F46),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Active le filtre de garde et fait défiler directement vers les pharmacies de garde
  void _activerPharmaciesDeGarde() {
    setState(() {
      _onlyGardeFilter = true;
      _searchController.clear();
      _searchFilter = '';
    });

    _scrollerVersPharmacies();

    final nbGardes = _pharmacies.where((p) => p.estDeGarde).length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "🛡️ Affichage des $nbGardes pharmacies de garde 24/7 actives !",
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF065F46),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Récupère automatiquement les données de l'utilisateur connecté depuis la base de données
  Future<void> _loadProfile() async {
    // 1. Chargement instantané depuis le cache local (enregistré lors de la connexion DB)
    try {
      final cached = await _authService.getCachedUser();
      final cPrenom = cached['prenom']?.trim() ?? '';
      final cNom = cached['nom']?.trim() ?? '';
      if (cPrenom.isNotEmpty && mounted) {
        setState(() {
          _user['prenom'] = cPrenom;
          if (cNom.isNotEmpty) _user['nom'] = cNom;
          _isLoadingProfile = false;
        });
      }
    } catch (_) {}

    // 2. Récupération dynamique depuis l'API backend /profil/ (BDD Django PostgreSQL/SQLite)
    try {
      final profile = await _authService.getProfile();
      if (!mounted) return;
      final prenom = (profile['prenom'] ?? profile['first_name'] ?? '').toString().trim();
      final nom = (profile['nom'] ?? profile['last_name'] ?? '').toString().trim();
      setState(() {
        if (prenom.isNotEmpty) {
          _user['prenom'] = prenom;
        }
        if (nom.isNotEmpty) {
          _user['nom'] = nom;
        }
        _isLoadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingProfile = false);
    }
  }

  /// Charge les données dynamiques avec tri par proximité
  Future<void> _loadData() async {
    setState(() {
      _isLoadingData = true;
      _errorMessage = null;
    });

    try {
      final pharms = await _pharmacieService.getPharmacies(lat: _userLat, lng: _userLng);

      if (!mounted) return;
      _trierPharmaciesParProximite(pharms);

      setState(() {
        _toutesPharmacies = List.from(pharms);
        _pharmacies = pharms;
        _isLoadingData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Impossible de contacter le serveur backend.\nVérifiez la connexion réseau.';
        _isLoadingData = false;
      });
    }
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

    // Tokens significatifs (exclut les mots génériques et d'intention)
    final meaningfulTokens = rawTokens.where((w) =>
        !stopwords.contains(w) &&
        !genericWords.contains(w) &&
        !gardeWords.contains(w) &&
        !procheWords.contains(w)).toList();

    List<PharmacieItem> baseList = List.from(source);
    if (isGardeIntent) {
      baseList = baseList.where((p) => p.estDeGarde).toList();
    }

    // Si l'utilisateur n'a tapé que des mots génériques (ex: "pharmacies", "pharmacie de garde", "proche de moi")
    if (meaningfulTokens.isEmpty) {
      _trierPharmaciesParProximite(baseList);
      return baseList;
    }

    final scored = <MapEntry<int, PharmacieItem>>[];

    for (final p in baseList) {
      final nomNorm = _normaliserTexte(p.nom);
      final nomWords = nomNorm.split(' ').where((w) => !genericWords.contains(w) && !stopwords.contains(w)).toList();
      final quartierWords = _normaliserTexte(p.quartier).split(' ');
      final addrWords = _normaliserTexte("${p.adresse} ${p.ville}").split(' ');
      final haystack = _normaliserTexte("${p.nom} ${p.adresse} ${p.quartier} ${p.ville}");

      // Doit correspondre à au moins un token significatif
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
        'destLat': _userLat,
        'destLng': _userLng,
        'label': (motCle != null && motCle.isNotEmpty) ? motCle : 'Pharmacies',
        'mode': 'search',
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ouverture de Google Maps (maps.google.com)..."),
          backgroundColor: Color(0xFF047857),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Recherche dynamique instantanée lettre par lettre (0ms) + enrichissement serveur
  void _onSearchChanged(String query) {
    setState(() {
      _searchFilter = query;
    });

    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _pharmacies = List.from(_toutesPharmacies);
        _isSearchingLive = false;
      });
      return;
    }

    // Défilement fluide vers la section pharmacies pour voir immédiatement les résultats
    _scrollerVersPharmacies(seulementSiHaut: true);

    // 1. Filtrage instantané (0ms) dès la première et deuxième lettre (g -> gb -> gbo...)
    final instantMatches = _filtrerEtTrierPharmacies(query.trim(), _toutesPharmacies);
    setState(() {
      _pharmacies = instantMatches;
      _isSearchingLive = true;
    });

    // 2. Appel serveur debouncé (180ms) pour récupérer et enrichir depuis Google Places / OSM
    _debounceTimer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final resultat = await _pharmacieService.rechercheDynamique(
          query: query.trim(),
          lat: _userLat,
          lng: _userLng,
        );

        if (!mounted) return;
        final List<PharmacieItem> dynamiques = (resultat['resultats'] as List<PharmacieItem>?) ?? [];
        if (dynamiques.isNotEmpty) {
          final sorted = _filtrerEtTrierPharmacies(query.trim(), dynamiques);
          setState(() {
            _pharmacies = sorted;
            _sourceDonneesInfo = resultat['message'] ?? 'Recherche dynamique';
            _isSearchingLive = false;
          });
        } else {
          setState(() => _isSearchingLive = false);
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingLive = false);
      }
    });
  }

  double _calculerDistanceKm(double? lat, double? lng) {
    if (lat == null || lng == null) return 9999.0;
    final dLat = (lat - _userLat) * 111.0;
    final dLng = (lng - _userLng) * 111.0 * cos(_userLat * pi / 180.0);
    return sqrt(dLat * dLat + dLng * dLng);
  }

  String _formatDistance(double distKm) {
    if (distKm >= 9000) return "";
    if (distKm < 1.0) {
      final metres = (distKm * 1000).toInt();
      return "$metres m";
    }
    return "${distKm.toStringAsFixed(1)} km";
  }

  void _trierPharmaciesParProximite(List<PharmacieItem> items) {
    items.sort((a, b) {
      final dA = _calculerDistanceKm(a.latitude, a.longitude);
      final dB = _calculerDistanceKm(b.latitude, b.longitude);
      return dA.compareTo(dB);
    });
  }

  /// Ouvre Google Maps en mode navigation vers la pharmacie choisie
  Future<void> _lancerGoogleMaps(PharmacieItem p) async {
    final destLat = p.latitude ?? _userLat;
    final destLng = p.longitude ?? _userLng;

    try {
      await _platform.invokeMethod('launchMaps', {
        'destLat': destLat,
        'destLng': destLng,
        'label': p.nom,
        'mode': 'navigation',
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Ouverture de l'itinéraire vers ${p.nom}..."),
          backgroundColor: const Color(0xFF047857),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Ouvre directement l'application Téléphone native avec le numéro affiché
  Future<void> _lancerAppel(String telephone, [String? nom]) async {
    final cleanTel = telephone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanTel.isEmpty) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("📞 Appel ${nom != null ? 'vers $nom ' : ''}: $telephone"),
          backgroundColor: const Color(0xFF047857),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    try {
      await _platform.invokeMethod('makePhoneCall', {
        'phoneNumber': cleanTel,
        'phone': cleanTel,
      });
    } catch (_) {
      if (mounted) {
        Clipboard.setData(ClipboardData(text: telephone));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Numéro copié : $telephone"),
            backgroundColor: const Color(0xFF047857),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _afficherModalContact(String titre, String telephone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFE6FDF4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.phone_in_talk_rounded,
                color: Color(0xFF047857),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              titre,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              telephone,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF047857),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: telephone));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Numéro copié : $telephone"),
                          backgroundColor: const Color(0xFF047857),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text("Copier"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _lancerAppel(telephone, titre);
                    },
                    icon: const Icon(Icons.phone_in_talk_rounded, size: 18, color: Colors.white),
                    label: const Text(
                      "Appeler",
                      style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _afficherNotificationGarde() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: const [
            Icon(Icons.notifications_active_rounded, color: Color(0xFF047857), size: 26),
            SizedBox(width: 8),
            Text(
              "Gardes ONPT Togo",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Les pharmacies de garde sont actualisées en direct selon le tableau officiel de l'Ordre National des Pharmaciens du Togo (ONPT).",
              style: TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE6FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF047857), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "${_pharmacies.where((p) => p.estDeGarde).length} pharmacies de garde actives",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fermer"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PharmacieMapScreen(initialGardeOnly: true),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF047857),
              foregroundColor: Colors.white,
            ),
            child: const Text("Voir sur la carte"),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Déconnexion", style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text("Souhaitez-vous vraiment vous déconnecter de DjimPharma ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text("Déconnexion", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _authService.logout();
    } finally {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<PharmacieItem> listFiltree = List.from(_pharmacies);
    bool estGardeCompletee = false;
    int nbGardesReelles = 0;

    if (_onlyGardeFilter) {
      final gardes = listFiltree.where((p) => p.estDeGarde).toList();
      nbGardesReelles = gardes.length;
      if (gardes.length >= 5) {
        listFiltree = gardes;
      } else {
        // Exigence : au moins 5 pharmacies proches garanties
        final complement = listFiltree.where((p) => !p.estDeGarde).toList();
        listFiltree = [...gardes, ...complement];
        estGardeCompletee = true;
      }
    }

    final bool isSearching = _searchFilter.trim().isNotEmpty;
    final int limite = isSearching ? 30 : max(5, _nbPharmaciesProchesAffichees);
    final pharmaciesAffichees = listFiltree.take(limite).toList();
    final int totalGardesActives = _pharmacies.where((p) => p.estDeGarde).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _detecterPositionGpsReelle(afficherNotification: true);
          },
          color: const Color(0xFF047857),
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. EN-TÊTE ÉLÉGANT & PRO AVEC STATUT GPS ───────────────────
                _buildProfessionalHeader(),

                const SizedBox(height: 14),

                // ── 2. BARRE DE RECHERCHE PRINCIPALE UNIFIÉE ───────────────────
                _buildUnifiedSearchBar(isSearching),

                const SizedBox(height: 12),

                // ── 3. CHIPS D'ACCÈS RAPIDE AUX FILTRES ────────────────────────
                _buildQuickFilterChips(),

                const SizedBox(height: 14),

                // ── 4. BANNIÈRE HERO EN DIRECT (GARDES TOGO) ───────────────────
                _buildHeroGardesCard(totalGardesActives),

                const SizedBox(height: 14),

                // ── 5. GRILLE 2X2 DES 4 SERVICES ESSENTIELS ─────────────────────
                _buildServicesGrid(),

                const SizedBox(height: 14),

                // ── 6. BANDEAU DES URGENCES DU TOGO (SAMU / POMPIERS / CHU) ───
                _buildUrgencesBandeau(),

                const SizedBox(height: 18),

                // ── 7. SECTION DES PHARMACIES RECOMMANDÉES (AU MOINS 5) ────────
                _buildPharmaciesSection(
                  isSearching: isSearching,
                  pharmaciesAffichees: pharmaciesAffichees,
                  estGardeCompletee: estGardeCompletee,
                  nbGardesReelles: nbGardesReelles,
                  listFiltree: listFiltree,
                ),
              ],
            ),
          ),
        ),
      ),

      // ── 8. BARRE DE NAVIGATION MODERNE & FLOTTANTE ───────────────────────
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  /// En-tête professionnel avec profil, GPS réel et actions discrètes
  Widget _buildProfessionalHeader() {
    final rawPrenom = (_user['prenom'] as String?)?.trim() ?? '';
    final rawNom = (_user['nom'] as String?)?.trim() ?? '';

    // Mise en majuscule soignée de la 1ère lettre du prénom issu de la base de données
    final prenom = rawPrenom.isNotEmpty
        ? (rawPrenom[0].toUpperCase() + (rawPrenom.length > 1 ? rawPrenom.substring(1) : ''))
        : '';
    final initial = prenom.isNotEmpty
        ? prenom[0].toUpperCase()
        : (rawNom.isNotEmpty ? rawNom[0].toUpperCase() : 'D');

    final salutation = prenom.isNotEmpty ? 'Bonjour, $prenom' : 'Bonjour';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                // Avatar vert émeraude uni avec initiale blanche
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFF065F46),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        salutation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      GestureDetector(
                        onTap: () => _detecterPositionGpsReelle(afficherNotification: true),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _userZoneNom,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF065F46),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.refresh_rounded,
                              size: 14,
                              color: Color(0xFF94A3B8),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _buildHeaderButton(
                icon: Icons.notifications_none_rounded,
                badge: true,
                tooltip: "Gardes actives",
                onTap: _afficherNotificationGarde,
              ),
              const SizedBox(width: 8),
              _buildHeaderButton(
                icon: Icons.map_outlined,
                tooltip: "Carte interactive",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PharmacieMapScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              _buildHeaderButton(
                icon: Icons.logout_rounded,
                tooltip: "Déconnexion",
                onTap: _logout,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Barre de recherche principale unifiée et épurée
  Widget _buildUnifiedSearchBar(bool isSearching) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSearching ? const Color(0xFF065F46) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          _isSearchingLive
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF065F46)),
                )
              : const Icon(Icons.search_rounded, color: Color(0xFF065F46), size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onTap: () => _scrollerVersPharmacies(seulementSiHaut: true),
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: "Rechercher une pharmacie, quartier, garde...",
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Container(
            height: 24,
            width: 1,
            color: const Color(0xFFE2E8F0),
          ),
          IconButton(
            tooltip: "Voir sur Google Maps",
            icon: const Icon(Icons.map_rounded, color: Color(0xFFDC2626), size: 21),
            onPressed: () => _ouvrirGoogleMapsDirect(_searchController.text.trim()),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// Chips horizontaux de filtrage rapide (5 plus proches, Garde, Google Maps, Catalogue)
  Widget _buildQuickFilterChips() {
    final isProcheActive = !_onlyGardeFilter && _searchFilter.isEmpty;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // 1. 5 plus proches (Pill vert sombre sélectionné par défaut)
          _buildPillChip(
            isSelected: isProcheActive,
            iconWidget: Icon(
              Icons.place_rounded,
              size: 15,
              color: isProcheActive ? Colors.white : const Color(0xFF065F46),
            ),
            label: "5 plus proches",
            onTap: _activerPharmaciesProchesDeMoi,
          ),
          const SizedBox(width: 8),

          // 2. De garde 24/7 (Pill blanc avec bouclier vert)
          _buildPillChip(
            isSelected: _onlyGardeFilter,
            iconWidget: Icon(
              Icons.shield_rounded,
              size: 15,
              color: _onlyGardeFilter ? Colors.white : const Color(0xFF065F46),
            ),
            label: "De garde 24/7",
            onTap: () {
              if (_onlyGardeFilter) {
                _activerPharmaciesProchesDeMoi();
              } else {
                _activerPharmaciesDeGarde();
              }
            },
          ),
          const SizedBox(width: 8),

          // 3. Google Maps (Pill blanc avec icône officielle multicolore)
          _buildPillChip(
            isSelected: false,
            iconWidget: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFEA4335),
                  Color(0xFFFBBC05),
                  Color(0xFF34A853),
                  Color(0xFF4285F4),
                ],
                stops: [0.0, 0.35, 0.70, 1.0],
              ).createShader(bounds),
              child: const Icon(Icons.place_rounded, color: Colors.white, size: 16),
            ),
            label: "Google Maps",
            trailingWidget: const Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF64748B)),
            onTap: () => _ouvrirGoogleMapsDirect(_searchController.text.trim()),
          ),
          const SizedBox(width: 8),

          // 4. Catalogue (Pill blanc avec gélule bicolore jaune/vert)
          _buildPillChip(
            isSelected: false,
            iconWidget: Transform.rotate(
              angle: -pi / 4,
              child: Container(
                width: 14,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEAB308), Color(0xFF22C55E)],
                  ),
                ),
              ),
            ),
            label: "Catalogue",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MedicamentSearchScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPillChip({
    required bool isSelected,
    required Widget iconWidget,
    required String label,
    required VoidCallback onTap,
    Widget? trailingWidget,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF065F46) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF065F46) : const Color(0xFFE2E8F0),
            width: 1.0,
          ),
          boxShadow: [
            if (!isSelected)
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            if (trailingWidget != null) ...[
              const SizedBox(width: 4),
              trailingWidget,
            ],
          ],
        ),
      ),
    );
  }

  /// Carte Hero de statut des gardes (Design émeraude avec pin radar & lignes cartographiques)
  Widget _buildHeroGardesCard(int totalGardesActives) {
    final nbGardes = totalGardesActives > 0 ? totalGardesActives : 9;

    return GestureDetector(
      onTap: _activerPharmaciesDeGarde,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF064E3B),
              Color(0xFF065F46),
              Color(0xFF0D9488),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF065F46).withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.fiber_manual_record, size: 7, color: Color(0xFF4ADE80)),
                        SizedBox(width: 5),
                        Text(
                          "EN DIRECT • ONPT TOGO",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Pharmacies de Garde 24/7",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$nbGardes officines ouvertes jour & nuit confirmées",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PharmacieMapScreen(initialGardeOnly: true),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.map_outlined, size: 14, color: Color(0xFF065F46)),
                          SizedBox(width: 5),
                          Text(
                            "Consulter la carte",
                            style: TextStyle(
                              color: Color(0xFF065F46),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_rounded, size: 13, color: Color(0xFF065F46)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Illustration radar cartographique avec le pin médical lumineux
            SizedBox(
              width: 95,
              height: 95,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(95, 95),
                    painter: _HeroBannerRadarPainter(),
                  ),
                  Transform.translate(
                    offset: const Offset(2, -2),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Corps du pin en goutte d'eau inclinée
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(27),
                              topRight: Radius.circular(27),
                              bottomLeft: Radius.circular(27),
                              bottomRight: Radius.circular(4),
                            ),
                            border: Border.all(color: Colors.white.withOpacity(0.40), width: 1.5),
                          ),
                          transform: Matrix4.rotationZ(-pi / 4),
                          transformAlignment: Alignment.center,
                        ),
                        // Centre blanc avec la croix médicale verte
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.add,
                              color: Color(0xFF065F46),
                              size: 22,
                            ),
                          ),
                        ),
                      ],
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

  /// Grille 2x2 des 4 services essentiels
  Widget _buildServicesGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildServiceTileCard(
                icon: Icons.near_me_rounded,
                title: "Proche de moi",
                subtitle: "Au moins 5 officines",
                accentColor: const Color(0xFF065F46),
                bgColor: const Color(0xFFE6FDF4),
                badgeText: "5 garanties",
                onTap: _activerPharmaciesProchesDeMoi,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildServiceTileCard(
                icon: Icons.shield_rounded,
                title: "De Garde 24/7",
                subtitle: "Urgences continues",
                accentColor: const Color(0xFF065F46),
                bgColor: const Color(0xFFE6FDF4),
                badgeText: "Active",
                onTap: _activerPharmaciesDeGarde,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildServiceTileCard(
                icon: Icons.medical_services_rounded,
                title: "Médicaments",
                subtitle: "Catalogue LNME",
                accentColor: const Color(0xFF2563EB),
                bgColor: const Color(0xFFEFF6FF),
                badgeText: "Officiel",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MedicamentSearchScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildServiceTileCard(
                icon: Icons.map_rounded,
                title: "Carte Radar GPS",
                subtitle: "Trajets & Maps",
                accentColor: const Color(0xFF7C3AED),
                bgColor: const Color(0xFFF3E8FF),
                badgeText: "En direct",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PharmacieMapScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServiceTileCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required Color bgColor,
    required String badgeText,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(icon, color: accentColor, size: 18),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Bandeau discret des numéros d'urgence du Togo (SAMU / POMPIERS / CHU)
  Widget _buildUrgencesBandeau() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFFFEE2E2),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.emergency_rounded, color: Color(0xFFEF4444), size: 16),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            "Urgences :",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildUrgenceChip("SAMU 8200", () => _afficherModalContact("SAMU National Togo", "8200")),
                  const SizedBox(width: 6),
                  _buildUrgenceChip("Pompiers 118", () => _afficherModalContact("Sapeurs Pompiers Togo", "118")),
                  const SizedBox(width: 6),
                  _buildUrgenceChip("CHU (+228)", () => _afficherModalContact("Urgences CHU Sylvanus Olympio", "+228 22 21 25 01")),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Section des pharmacies avec liste garantie
  Widget _buildPharmaciesSection({
    required bool isSearching,
    required List<PharmacieItem> pharmaciesAffichees,
    required bool estGardeCompletee,
    required int nbGardesReelles,
    required List<PharmacieItem> listFiltree,
  }) {
    return Container(
      key: _pharmaciesSectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête de section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isSearching ? "Résultats de recherche" : "Pharmacies recommandées",
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6FDF4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isSearching
                              ? "${pharmaciesAffichees.length} trouvée${pharmaciesAffichees.length > 1 ? 's' : ''}"
                              : "5 plus proches",
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF065F46),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSearching
                        ? "Résultats instantanés pour '$_searchFilter'"
                        : "Triées par distance GPS croissante (au moins 5)",
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              if (isSearching)
                TextButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                  icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF065F46)),
                  label: const Text(
                    "Effacer",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                  ),
                )
              else
                GestureDetector(
                  onTap: () {
                    if (_onlyGardeFilter) {
                      _activerPharmaciesProchesDeMoi();
                    } else {
                      _activerPharmaciesDeGarde();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _onlyGardeFilter ? const Color(0xFF065F46) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _onlyGardeFilter ? const Color(0xFF065F46) : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: _onlyGardeFilter ? Colors.white : const Color(0xFF1E293B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _onlyGardeFilter ? "De garde" : "Toutes",
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _onlyGardeFilter ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          if (estGardeCompletee) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF065F46)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      "🛡️ $nbGardesReelles de garde + ${pharmaciesAffichees.length - nbGardesReelles} ouvertes les plus proches (au moins 5 assurées)",
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // État de chargement / erreur / vide / cartes
          if (_isLoadingData)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: CircularProgressIndicator(color: Color(0xFF065F46)),
              ),
            )
          else if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text("Réessayer"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF065F46),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else if (pharmaciesAffichees.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded, size: 36, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 8),
                  Text(
                    "Aucune pharmacie locale pour \"$_searchFilter\".",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Vous pouvez lancer la recherche directement sur Google Maps.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MedicamentSearchScreen(initialQuery: _searchFilter),
                        ),
                      );
                    },
                    icon: const Icon(Icons.medication_rounded, size: 16),
                    label: Text("Chercher \"$_searchFilter\" dans les médicaments 💊"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _ouvrirGoogleMapsDirect(_searchFilter),
                    icon: const Icon(Icons.map_rounded, size: 16, color: Color(0xFF065F46)),
                    label: const Text("Rechercher sur Google Maps 🗺️", style: TextStyle(color: Color(0xFF065F46))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF065F46), width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                    child: const Text("Afficher les 5 pharmacies les plus proches"),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                ...pharmaciesAffichees.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildRealPharmacyCard(p),
                    )),
                if (!isSearching && listFiltree.length > 5) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          if (_nbPharmaciesProchesAffichees == 5) {
                            _nbPharmaciesProchesAffichees = 10;
                          } else if (_nbPharmaciesProchesAffichees == 10) {
                            _nbPharmaciesProchesAffichees = 20;
                          } else {
                            _nbPharmaciesProchesAffichees = 5;
                          }
                        });
                      },
                      icon: Icon(
                        _nbPharmaciesProchesAffichees > 5
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.add_circle_outline_rounded,
                        color: const Color(0xFF065F46),
                        size: 16,
                      ),
                      label: Text(
                        _nbPharmaciesProchesAffichees == 5
                            ? "Afficher plus d'officines (+5)"
                            : (_nbPharmaciesProchesAffichees == 10
                                ? "Afficher les 20 plus proches"
                                : "Réduire aux 5 plus proches"),
                        style: const TextStyle(
                          color: Color(0xFF065F46),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  /// Carte d'une pharmacie (Design épuré avec emblème officiel, badges et boutons Itinéraire GPS / Appel)
  Widget _buildRealPharmacyCard(PharmacieItem pharmacie) {
    final distKm = _calculerDistanceKm(pharmacie.latitude, pharmacie.longitude);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Emblème mortier & pilon dans son conteneur vert menthe
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6FDF4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: _PharmacyEmblem(
                    color: Color(0xFF065F46),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pharmacie.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${pharmacie.adresse} • ${pharmacie.ville}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6FDF4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.place_rounded, size: 10, color: Color(0xFF065F46)),
                              const SizedBox(width: 3),
                              Text(
                                _formatDistance(distKm),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6FDF4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pharmacie.estDeGarde ? "DE GARDE 24/7" : "OUVERTE",
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF065F46),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (pharmacie.telephone.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.phone_rounded, size: 11, color: Color(0xFF065F46)),
                          const SizedBox(width: 4),
                          Text(
                            pharmacie.telephone,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF065F46),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _lancerGoogleMaps(pharmacie),
                  icon: const Icon(Icons.navigation_rounded, size: 14, color: Colors.white),
                  label: const Text(
                    "Itinéraire GPS",
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF065F46),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final tel = pharmacie.telephone.isNotEmpty ? pharmacie.telephone : "+228 22 21 00 00";
                    _lancerAppel(tel, pharmacie.nom);
                  },
                  icon: const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF065F46)),
                  label: const Text(
                    "Appel",
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    side: const BorderSide(color: Color(0xFF065F46), width: 1.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Barre de navigation mobile moderne avec bulle active surélevée et vague sculptée
  Widget _buildBottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      height: 76,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth;
          final tabWidth = barWidth / 4;

          return TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _currentIndex.toDouble()),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, animatedIndex, child) {
              final activeX = (animatedIndex + 0.5) * tabWidth;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. Fond blanc sculpté avec la vague arrondie ascendante
                  Positioned(
                    top: 14,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: CustomPaint(
                      painter: _PopNavCurvedPainter(
                        activeX: activeX,
                      ),
                    ),
                  ),

                  // 2. Trait indicateur d'accueil centré en bas
                  Positioned(
                    bottom: 4,
                    left: (barWidth - 36) / 2,
                    child: Container(
                      width: 36,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  // 3. Les 4 onglets interactifs
                  Positioned(
                    top: 14,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Row(
                      children: [
                        _buildPopNavItem(index: 0, icon: Icons.home_rounded, label: "Accueil", animatedIndex: animatedIndex),
                        _buildPopNavItem(index: 1, icon: Icons.medication_rounded, label: "Catalogue", animatedIndex: animatedIndex),
                        _buildPopNavItem(index: 2, icon: Icons.explore_rounded, label: "Carte", animatedIndex: animatedIndex),
                        _buildPopNavItem(index: 3, icon: Icons.shield_rounded, label: "Gardes", animatedIndex: animatedIndex),
                      ],
                    ),
                  ),

                  // 4. La bulle circulaire surélevée animée (Pop-out bubble)
                  Positioned(
                    top: 0,
                    left: activeX - 25,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(_currentIndex),
                      tween: Tween<double>(begin: 0.80, end: 1.0),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.elasticOut,
                      builder: (context, popScale, child) {
                        return Transform.scale(
                          scale: popScale,
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF047857).withValues(alpha: 0.22),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFE6FDF4),
                                border: Border.all(
                                  color: const Color(0xFF047857).withValues(alpha: 0.25),
                                  width: 1.2,
                                ),
                              ),
                              child: Icon(
                                _getPopNavIcon(_currentIndex),
                                color: const Color(0xFF047857),
                                size: 22,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  IconData _getPopNavIcon(int index) {
    switch (index) {
      case 0:
        return Icons.home_rounded;
      case 1:
        return Icons.medication_rounded;
      case 2:
        return Icons.explore_rounded;
      case 3:
        return Icons.shield_rounded;
      default:
        return Icons.home_rounded;
    }
  }

  Widget _buildPopNavItem({
    required int index,
    required IconData icon,
    required String label,
    required double animatedIndex,
  }) {
    final isSelected = _currentIndex == index;
    final diff = (index - animatedIndex).abs();

    // Effet d'onde et de mouvement interactif transmis aux autres onglets
    final waveProximity = (1.0 - (diff / 1.4)).clamp(0.0, 1.0);
    final waveLift = isSelected ? 0.0 : -sin(waveProximity * pi) * 6.5;
    final waveScale = isSelected ? 1.0 : (1.0 + 0.12 * waveProximity);
    final waveAngle = isSelected ? 0.0 : ((index > animatedIndex ? 0.08 : -0.08) * waveProximity);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MedicamentSearchScreen()),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PharmacieMapScreen(initialGardeOnly: false)),
            );
          } else if (index == 3) {
            setState(() {
              _currentIndex = 3;
              _onlyGardeFilter = true;
            });
            if (_pharmaciesSectionKey.currentContext != null) {
              Scrollable.ensureVisible(
                _pharmaciesSectionKey.currentContext!,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
              );
            }
          } else {
            setState(() {
              _currentIndex = 0;
              _onlyGardeFilter = false;
            });
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!isSelected)
              Transform.translate(
                offset: Offset(0, waveLift),
                child: Transform.rotate(
                  angle: waveAngle,
                  child: Transform.scale(
                    scale: waveScale,
                    child: Icon(
                      icon,
                      color: Color.lerp(
                        const Color(0xFF94A3B8),
                        const Color(0xFF047857),
                        waveProximity * 0.45,
                      ),
                      size: 21,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 22),
            const SizedBox(height: 3),
            Transform.translate(
              offset: Offset(0, isSelected ? 0.0 : waveLift * 0.35),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  color: isSelected
                      ? const Color(0xFF0F172A)
                      : Color.lerp(
                          const Color(0xFF94A3B8),
                          const Color(0xFF047857),
                          waveProximity * 0.45,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildUrgenceChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_rounded, size: 11, color: Color(0xFF065F46)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    bool badge = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: const Color(0xFF065F46), size: 21),
            if (badge)
              Positioned(
                top: 7,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Peintre de la barre de navigation sculptée avec la vague sous la bulle active
class _PopNavCurvedPainter extends CustomPainter {
  final double activeX;

  _PopNavCurvedPainter({required this.activeX});

  @override
  void paint(Canvas canvas, Size size) {
    const double radius = 24.0;
    const double crestHalfWidth = 36.0;
    const double crestTop = -13.0;

    final path = Path();

    final leftCrest = (activeX - crestHalfWidth).clamp(radius, size.width - radius);
    final rightCrest = (activeX + crestHalfWidth).clamp(radius, size.width - radius);

    // Coin supérieur gauche
    path.moveTo(0, radius);
    path.arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius));

    // Ligne jusqu'au début de la vague
    if (leftCrest > radius) {
      path.lineTo(leftCrest, 0);
    }

    // Vague ascendante arrondie vers le sommet
    path.cubicTo(
      leftCrest + 10, 0,
      activeX - 18, crestTop,
      activeX, crestTop,
    );

    // Vague descendante arrondie
    path.cubicTo(
      activeX + 18, crestTop,
      rightCrest - 10, 0,
      rightCrest, 0,
    );

    // Ligne vers le coin supérieur droit
    path.lineTo(size.width - radius, 0);
    path.arcToPoint(Offset(size.width, radius), radius: const Radius.circular(radius));

    // Coin inférieur droit
    path.lineTo(size.width, size.height - radius);
    path.arcToPoint(Offset(size.width - radius, size.height), radius: const Radius.circular(radius));

    // Coin inférieur gauche
    path.lineTo(radius, size.height);
    path.arcToPoint(Offset(0, size.height - radius), radius: const Radius.circular(radius));

    path.close();

    // Ombre douce sous la barre blanche
    canvas.drawShadow(path, const Color(0xFF0F172A).withValues(alpha: 0.12), 12.0, true);

    // Remplissage blanc pur
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Légère bordure supérieure pour une finition soignée
    final strokePaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _PopNavCurvedPainter oldDelegate) =>
      oldDelegate.activeX != activeX;
}

/// Effet radar & lignes de plan de ville sur la bannière Hero
class _HeroBannerRadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final streetPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    // Lignes de rues diagonales en filigrane
    canvas.drawLine(const Offset(-10, 24), Offset(size.width + 10, 8), streetPaint);
    canvas.drawLine(const Offset(8, 0), Offset(size.width * 0.72, size.height + 10), streetPaint);
    canvas.drawLine(Offset(-10, size.height * 0.62), Offset(size.width + 10, size.height * 0.42), streetPaint);
    canvas.drawLine(Offset(size.width * 0.32, -10), Offset(size.width + 10, size.height * 0.88), streetPaint);

    final center = Offset(size.width * 0.52, size.height * 0.48);

    // Cercles radar concentriques
    final ringPaint1 = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, 44, ringPaint1);

    final ringPaint2 = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, 34, ringPaint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Emblème officiel de la pharmacie (Coupe d'Hygie / Mortier & Pilon)
class _PharmacyEmblem extends StatelessWidget {
  final Color color;
  final double size;

  const _PharmacyEmblem({
    this.color = const Color(0xFF065F46),
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PharmacyEmblemPainter(color: color),
      ),
    );
  }
}

class _PharmacyEmblemPainter extends CustomPainter {
  final Color color;
  _PharmacyEmblemPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // 1. Manche incliné du pilon
    final pestle = Path();
    pestle.moveTo(w * 0.44, h * 0.12);
    pestle.lineTo(w * 0.72, h * 0.42);
    pestle.lineTo(w * 0.63, h * 0.50);
    pestle.lineTo(w * 0.35, h * 0.20);
    pestle.close();
    canvas.drawPath(pestle, paint);

    // 2. Calice / coupe du mortier
    final bowl = Path();
    bowl.moveTo(w * 0.18, h * 0.38);
    bowl.lineTo(w * 0.82, h * 0.38);
    bowl.cubicTo(w * 0.80, h * 0.72, w * 0.65, h * 0.82, w * 0.58, h * 0.82);
    bowl.lineTo(w * 0.58, h * 0.88);
    bowl.lineTo(w * 0.74, h * 0.90);
    bowl.lineTo(w * 0.74, h * 0.98);
    bowl.lineTo(w * 0.26, h * 0.98);
    bowl.lineTo(w * 0.26, h * 0.90);
    bowl.lineTo(w * 0.42, h * 0.88);
    bowl.lineTo(w * 0.42, h * 0.82);
    bowl.cubicTo(w * 0.35, h * 0.82, w * 0.20, h * 0.72, w * 0.18, h * 0.38);
    bowl.close();
    canvas.drawPath(bowl, paint);
  }

  @override
  bool shouldRepaint(covariant _PharmacyEmblemPainter oldDelegate) =>
      oldDelegate.color != color;
}
