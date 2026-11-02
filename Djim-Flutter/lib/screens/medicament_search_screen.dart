import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/medicament_service.dart';
import '../services/pharmacie_service.dart';

class MedicamentSearchScreen extends StatefulWidget {
  final String? initialQuery;

  const MedicamentSearchScreen({super.key, this.initialQuery});

  @override
  State<MedicamentSearchScreen> createState() => _MedicamentSearchScreenState();
}

class _MedicamentSearchScreenState extends State<MedicamentSearchScreen> {
  double _userLat = 6.1365;
  double _userLng = 1.2185;

  Future<void> _detecterPositionGps() async {
    try {
      final res = await _platform.invokeMethod('getCurrentLocation');
      if (res != null && res is Map && mounted) {
        final lat = res['lat'] != null ? (res['lat'] as num).toDouble() : null;
        final lng = res['lng'] != null ? (res['lng'] as num).toDouble() : null;
        if (lat != null && lng != null) {
          setState(() {
            _userLat = lat;
            _userLng = lng;
          });
        }
      }
    } catch (_) {}
  }

  double _calculerDistanceKm(double? lat, double? lng) {
    if (lat == null || lng == null) return 9999.0;
    final dLat = (lat - _userLat) * 111.0;
    final dLng = (lng - _userLng) * 111.0 * cos(_userLat * pi / 180.0);
    return sqrt(dLat * dLat + dLng * dLng);
  }

  String _formatDistance(double distKm) {
    if (distKm >= 9000) return "Distance N/D";
    if (distKm < 1.0) {
      return "${(distKm * 1000).toInt()} m";
    }
    return "${distKm.toStringAsFixed(1)} km";
  }

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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ouverture de l'itinéraire Google Maps vers ${p.nom}..."),
            backgroundColor: const Color(0xFF047857),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _ouvrirGoogleMapsDirect([String? query]) async {
    try {
      await _platform.invokeMethod('launchMaps', {
        'destLat': _userLat,
        'destLng': _userLng,
        'label': (query != null && query.isNotEmpty) ? query : 'Pharmacie Lomé',
        'mode': 'search',
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Ouverture de Google Maps (maps.google.com)..."),
            backgroundColor: Color(0xFF047857),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static const _platform = MethodChannel('com.example.djim_flutter/map_launcher');

  final MedicamentService _medicamentService = MedicamentService();
  final PharmacieService _pharmacieService = PharmacieService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounceTimer;
  List<MedicamentItem> _medicaments = [];
  List<PharmacieItem> _pharmaciesDeGarde = [];
  List<String> _categories = [];
  String _selectedCategorie = "";
  bool _filtreEnStockSeulement = false;
  bool _afficherBanniereInfo = true;

  bool _isLoading = true;
  bool _isSearching = false;
  int _totalCount = 0;
  int _currentPage = 1;
  bool _hasMore = false;

  List<MedicamentItem> get _medicamentsAffiches {
    if (_filtreEnStockSeulement) {
      return _medicaments
          .where((m) => m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible')
          .toList();
    }
    return _medicaments;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
    }
    _detecterPositionGps();
    _chargerDonneesInitiales();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _chargerDonneesInitiales() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _medicamentService.chercherMedicaments(
          query: _searchController.text.trim(),
          page: 1,
        ),
        _medicamentService.getCategories(),
        _pharmacieService.getPharmacies(),
      ]);

      final searchRes = futures[0] as Map<String, dynamic>;
      final cats = futures[1] as List<String>;
      final allPharma = futures[2] as List<PharmacieItem>;

      if (mounted) {
        setState(() {
          _medicaments = (searchRes['results'] as List<MedicamentItem>?) ?? [];
          _totalCount = (searchRes['count'] as int?) ?? 0;
          _hasMore = searchRes['next'] != null;
          _categories = cats;
          _pharmaciesDeGarde = allPharma.where((p) => p.estDeGarde).toList();
          if (_pharmaciesDeGarde.isEmpty) {
            _pharmaciesDeGarde = allPharma.take(10).toList();
          }
          _pharmaciesDeGarde.sort((a, b) {
            final dA = _calculerDistanceKm(a.latitude, a.longitude);
            final dB = _calculerDistanceKm(b.latitude, b.longitude);
            return dA.compareTo(dB);
          });
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    setState(() => _isSearching = true);

    _debounceTimer = Timer(const Duration(milliseconds: 200), () async {
      try {
        final res = await _medicamentService.chercherMedicaments(
          query: query.trim(),
          page: 1,
          categorie: _selectedCategorie,
        );

        if (mounted) {
          setState(() {
            _medicaments = (res['results'] as List<MedicamentItem>?) ?? [];
            _totalCount = (res['count'] as int?) ?? 0;
            _hasMore = res['next'] != null;
            _currentPage = 1;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _filtrerParCategorie(String cat) {
    setState(() {
      _selectedCategorie = (_selectedCategorie == cat) ? "" : cat;
      _isLoading = true;
    });

    _medicamentService
        .chercherMedicaments(
      query: _searchController.text.trim(),
      page: 1,
      categorie: _selectedCategorie,
    )
        .then((res) {
      if (mounted) {
        setState(() {
          _medicaments = (res['results'] as List<MedicamentItem>?) ?? [];
          _totalCount = (res['count'] as int?) ?? 0;
          _hasMore = res['next'] != null;
          _currentPage = 1;
          _isLoading = false;
        });
      }
    });
  }

  String _nettoyerNomCategorie(String raw) {
    if (raw.isEmpty) return "";
    // Supprimer les préfixes numériques administratifs du LNME (ex: "1.1.1 Medicaments..." -> "Medicaments...")
    String cleaned = raw.replaceFirst(RegExp(r'^\s*[\d\.\-\_]+\s*'), '').trim();
    if (cleaned.isEmpty) return raw;
    // Mettre en forme agréable (première lettre majuscule, reste minuscule)
    return cleaned[0].toUpperCase() + cleaned.substring(1).toLowerCase();
  }

  Future<void> _chargerPlus() async {
    if (!_hasMore || _isLoading || _filtreEnStockSeulement) return;
    final nextPage = _currentPage + 1;

    try {
      final res = await _medicamentService.chercherMedicaments(
        query: _searchController.text.trim(),
        page: nextPage,
        categorie: _selectedCategorie,
      );

      final newItems = (res['results'] as List<MedicamentItem>?) ?? [];
      if (mounted) {
        setState(() {
          _medicaments.addAll(newItems);
          _currentPage = nextPage;
          _hasMore = res['next'] != null;
        });
      }
    } catch (_) {}
  }

  Future<void> _lancerAppel(String telephone) async {
    final cleanTel = telephone.replaceAll(RegExp(r'[^0-9+]'), '');
    try {
      await _platform.invokeMethod('makePhoneCall', {'phoneNumber': cleanTel});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Composez le : $cleanTel"),
            backgroundColor: const Color(0xFF047857),
          ),
        );
      }
    }
  }

  Future<void> _lancerGoogleMapsCoord(double? lat, double? lng, String label) async {
    final destLat = lat ?? _userLat;
    final destLng = lng ?? _userLng;
    try {
      await _platform.invokeMethod('launchMaps', {
        'destLat': destLat,
        'destLng': destLng,
        'label': label,
        'mode': 'navigation',
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ouverture de l'itinéraire vers $label..."),
            backgroundColor: const Color(0xFF047857),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _afficherModalPharmaciesEnStock(MedicamentItem medicament) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final pharmaciesDispo = medicament.pharmaciesDisponibles;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6FDF4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.verified_rounded, color: Color(0xFF047857), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          medicament.nom,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "En stock dans ${pharmaciesDispo.length} pharmacie${pharmaciesDispo.length > 1 ? 's' : ''} vérifiée${pharmaciesDispo.length > 1 ? 's' : ''}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF047857),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (medicament.prixIndicatif != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF047857), width: 1.1),
                      ),
                      child: Text(
                        medicament.prixIndicatif!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.inventory_2_rounded, color: Color(0xFF15803D), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Stocks synchronisés en direct. Prix garantis en Francs CFA (XOF) au comptoir.",
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "Officines disposant du médicament en stock :",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: pharmaciesDispo.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final s = pharmaciesDispo[index];
                    final distKm = _calculerDistanceKm(s.latitude, s.longitude);
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.6),
                          width: 1.3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6FDF4),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.local_pharmacy_rounded,
                                  color: Color(0xFF047857),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.nom,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      s.adresse.isNotEmpty ? s.adresse : s.ville,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6FDF4),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF047857), width: 1),
                                ),
                                child: Text(
                                  "${s.prix} FCFA",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF047857),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: s.statutStock == 'DISPONIBLE' ? const Color(0xFFE6FDF4) : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  s.statutStock == 'DISPONIBLE'
                                      ? "En stock (${s.quantite} dispo)"
                                      : "Stock limité (${s.quantite} restants)",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: s.statutStock == 'DISPONIBLE' ? const Color(0xFF047857) : const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                              if (distKm < 9000) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.near_me_rounded, size: 10, color: Color(0xFF64748B)),
                                      const SizedBox(width: 3),
                                      Text(
                                        _formatDistance(distKm),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const Spacer(),
                              OutlinedButton.icon(
                                onPressed: () {
                                  final tel = s.telephone.isNotEmpty ? s.telephone : "+228 22 21 00 00";
                                  _lancerAppel(tel);
                                },
                                icon: const Icon(Icons.phone_rounded, size: 12, color: Color(0xFF047857)),
                                label: const Text(
                                  "Appel",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF047857)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  side: const BorderSide(color: Color(0xFF047857), width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton.icon(
                                onPressed: () => _lancerGoogleMapsCoord(s.latitude, s.longitude, s.nom),
                                icon: const Icon(Icons.navigation_rounded, size: 12, color: Colors.white),
                                label: const Text(
                                  "Itinéraire",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF047857),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _afficherModalContactPharmacies(MedicamentItem medicament) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.80,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6FDF4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF047857), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Contacter une pharmacie",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          "Pour vérifier la disponibilité de : ${medicament.nom}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Raccourci Google Maps
              GestureDetector(
                onTap: () => _ouvrirGoogleMapsDirect("${medicament.nom} pharmacie Lomé"),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_rounded, color: Color(0xFF047857), size: 16),
                      SizedBox(width: 8),
                      Text(
                        "Localiser les pharmacies sur Google Maps",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.open_in_new_rounded, color: Color(0xFF64748B), size: 13),
                    ],
                  ),
                ),
              ),

              const Text(
                "Pharmacies les plus proches (triées par distance GPS) :",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 10),

              Expanded(
                child: ListView.separated(
                  itemCount: _pharmaciesDeGarde.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final p = _pharmaciesDeGarde[index];
                    final distKm = _calculerDistanceKm(p.latitude, p.longitude);
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: p.estDeGarde ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                          width: p.estDeGarde ? 1.4 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: p.estDeGarde ? const Color(0xFFE6FDF4) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  p.estDeGarde ? Icons.shield_rounded : Icons.local_pharmacy_rounded,
                                  color: p.estDeGarde ? const Color(0xFF047857) : const Color(0xFF64748B),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.nom,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      p.adresse.isNotEmpty ? "${p.adresse} • ${p.ville}" : p.ville,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: p.estDeGarde ? const Color(0xFF047857) : const Color(0xFFE2E8F0),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  p.estDeGarde ? "DE GARDE 🛡️" : "OUVERTE",
                                  style: TextStyle(
                                    color: p.estDeGarde ? Colors.white : const Color(0xFF475569),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6FDF4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.near_me_rounded, size: 11, color: Color(0xFF047857)),
                                    const SizedBox(width: 3),
                                    Text(
                                      _formatDistance(distKm),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF047857),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              OutlinedButton.icon(
                                onPressed: () {
                                  final tel = p.telephone.isNotEmpty ? p.telephone : "+228 22 21 00 00";
                                  _lancerAppel(tel);
                                },
                                icon: const Icon(Icons.phone_rounded, size: 12, color: Color(0xFF047857)),
                                label: const Text(
                                  "Appel",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF047857)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  side: const BorderSide(color: Color(0xFF047857), width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton.icon(
                                onPressed: () => _lancerGoogleMaps(p),
                                icon: const Icon(Icons.navigation_rounded, size: 12, color: Colors.white),
                                label: const Text(
                                  "Itinéraire",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF047857),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _afficherFicheMedicament(MedicamentItem m) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6FDF4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medication_rounded, color: Color(0xFF047857), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  m.nom,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                _buildFicheRow("DCI (Dénomination Commune)", m.dci.isNotEmpty ? m.dci : "-"),
                _buildFicheRow("Forme pharmaceutique", m.formePharmaceutique.isNotEmpty ? m.formePharmaceutique : "-"),
                _buildFicheRow("Dosage", m.dosage.isNotEmpty ? m.dosage : "-"),
                _buildFicheRow("Classe thérapeutique", _nettoyerNomCategorie(m.categorieTherapeutique).isNotEmpty ? _nettoyerNomCategorie(m.categorieTherapeutique) : "-"),
                _buildFicheRow("Niveau d'utilisation prescrit", m.niveauxSoins.isNotEmpty ? m.niveauxSoins : "ASC, USP, HD, CHR, CHU"),
                _buildFicheRow("Source réglementaire", m.sourceInformation),
                _buildFicheRow("Statut officiel", m.statutReglementaireDisplay),
                if (m.prixIndicatif != null) ...[
                  _buildFicheRow("Prix indicatif officiel", m.prixIndicatif!),
                  _buildFicheRow("Officines en stock", "${m.nombrePharmaciesDisponibles} pharmacie(s) partenaire(s)"),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible')
                        ? const Color(0xFFE6FDF4)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible')
                          ? const Color(0xFF10B981).withValues(alpha: 0.4)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible')
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        size: 16,
                        color: (m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible')
                            ? const Color(0xFF047857)
                            : const Color(0xFF475569),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible')
                              ? "Médicament disponible en officine avec stocks vérifiés."
                              : "Disponibilité vérifiable auprès des pharmacies de garde les plus proches.",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: (m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible')
                                ? const Color(0xFF047857)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Fermer", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                if (m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible') {
                  _afficherModalPharmaciesEnStock(m);
                } else {
                  _afficherModalContactPharmacies(m);
                }
              },
              icon: Icon(
                (m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible')
                    ? Icons.storefront_rounded
                    : Icons.phone_rounded,
                size: 14,
                color: Colors.white,
              ),
              label: Text(
                (m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible')
                    ? "Pharmacies en stock (${m.nombrePharmaciesDisponibles})"
                    : "Contacter pharmacie",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF047857),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFicheRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
          const SizedBox(height: 1),
          Text(value, style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final medicamentsVisibles = _medicamentsAffiches;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Catalogue Officiel Togo",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
            Text(
              "Arrêté N° 147/2021/MSHPAUS • LNME Togo",
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF047857),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE6FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, size: 13, color: Color(0xFF047857)),
                const SizedBox(width: 4),
                Text(
                  _filtreEnStockSeulement ? "${medicamentsVisibles.length} en stock" : "$_totalCount réf.",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1F5F9), height: 1),
        ),
      ),
      body: Column(
        children: [
          // ── BARRE DE RECHERCHE + FILTRES INTELLIGENTS ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: "DCI, marque, dosage (ex: Paracétamol, Panadol 500mg)...",
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      prefixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF047857)),
                              ),
                            )
                          : const Icon(Icons.search_rounded, color: Color(0xFF047857), size: 20),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                if (_categories.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length + 2,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, index) {
                        // 1. Bouton "Tous"
                        if (index == 0) {
                          final isSelected = _selectedCategorie.isEmpty && !_filtreEnStockSeulement;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedCategorie = "";
                                _filtreEnStockSeulement = false;
                              });
                              _filtrerParCategorie("");
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF047857) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF047857) : const Color(0xFFCBD5E1),
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF047857).withValues(alpha: 0.25),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.apps_rounded,
                                    size: 13,
                                    color: isSelected ? Colors.white : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    "Tous",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected ? Colors.white : const Color(0xFF334155),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // 2. Bouton "En stock direct"
                        if (index == 1) {
                          final isSelected = _filtreEnStockSeulement;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _filtreEnStockSeulement = !_filtreEnStockSeulement;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF047857) : const Color(0xFFE6FDF4),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF047857) : const Color(0xFF10B981).withValues(alpha: 0.5),
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF047857).withValues(alpha: 0.25),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: 13,
                                    color: isSelected ? Colors.white : const Color(0xFF047857),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    "En stock direct",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected ? Colors.white : const Color(0xFF047857),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // 3. Catégories thérapeutiques nettoyées
                        final cat = _categories[index - 2];
                        final isSelected = _selectedCategorie == cat && !_filtreEnStockSeulement;
                        final cleanTitle = _nettoyerNomCategorie(cat);

                        return GestureDetector(
                          onTap: () {
                            setState(() => _filtreEnStockSeulement = false);
                            _filtrerParCategorie(cat);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF047857) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF047857) : const Color(0xFFCBD5E1),
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF047857).withValues(alpha: 0.25),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              cleanTitle,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── BANNIÈRE INSTITUTIONNELLE PRO & FERMABLE (SANS COULEUR D'ALERTE) ──
          if (_afficherBanniereInfo) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF0FDF4), Color(0xFFECFDF5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFA7F3D0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF047857).withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF047857).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: Color(0xFF047857), size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Référentiel National LNME Togo",
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        Text(
                          "Prix indicatifs et contact direct garanti avec les officines de garde.",
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF047857),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _afficherBanniereInfo = false),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, size: 16, color: Color(0xFF047857)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── LISTE DES MÉDICAMENTS ──
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF047857)),
                  )
                : medicamentsVisibles.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6FDF4),
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: const Icon(Icons.medication_liquid_rounded, size: 42, color: Color(0xFF047857)),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _filtreEnStockSeulement
                                    ? "Aucun médicament en stock immédiat trouvé"
                                    : "Aucun résultat pour cette recherche",
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Essayez un nom commercial courant ou explorez ces suggestions :",
                                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  _buildSuggestionChip("Panadol"),
                                  _buildSuggestionChip("Paracétamol"),
                                  _buildSuggestionChip("Amoxicilline"),
                                  _buildSuggestionChip("Artéméther"),
                                  _buildSuggestionChip("Ibuprofène"),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (scrollInfo) {
                          if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                            _chargerPlus();
                          }
                          return false;
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: medicamentsVisibles.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (_, index) {
                            final m = medicamentsVisibles[index];
                            return _buildMedicamentCard(m);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String terme) {
    return ActionChip(
      onPressed: () {
        _searchController.text = terme;
        _onSearchChanged(terme);
      },
      avatar: const Icon(Icons.search_rounded, size: 14, color: Color(0xFF047857)),
      label: Text(
        terme,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF047857)),
      ),
      backgroundColor: const Color(0xFFE6FDF4),
      side: const BorderSide(color: Color(0xFFA7F3D0)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildMedicamentCard(MedicamentItem m) {
    final bool estEnStock = m.disponibiliteStatut == 'disponible' || m.disponibiliteStatut == 'stock_faible';
    final bool estStockFaible = m.disponibiliteStatut == 'stock_faible';
    final String formeClean = m.formePharmaceutique.trim();
    final String dciClean = m.dci.trim();
    final String nomClean = m.nom.trim();
    final String catClean = _nettoyerNomCategorie(m.categorieTherapeutique);

    // Déterminer l'icône et la palette de couleur selon la forme médicale
    IconData formeIcon = Icons.medication_rounded;
    Color iconColor = const Color(0xFF047857);
    Color iconBg = const Color(0xFFE6FDF4);

    final fLower = formeClean.toLowerCase();
    final nomLower = nomClean.toLowerCase();
    if (fLower.contains('inhal') || nomLower.contains('inhal')) {
      formeIcon = Icons.air_rounded;
      iconColor = const Color(0xFF7C3AED);
      iconBg = const Color(0xFFF5F3FF);
    } else if (fLower.contains('inject') || fLower.contains('perf') || fLower.contains('ampoule')) {
      formeIcon = Icons.vaccines_rounded;
      iconColor = const Color(0xFF2563EB);
      iconBg = const Color(0xFFEFF6FF);
    } else if (fLower.contains('sirop') || fLower.contains('solut') || fLower.contains('goutte') || fLower.contains('susp')) {
      formeIcon = Icons.water_drop_rounded;
      iconColor = const Color(0xFF0284C7);
      iconBg = const Color(0xFFF0F9FF);
    } else if (fLower.contains('pommade') || fLower.contains('crème') || fLower.contains('gel')) {
      formeIcon = Icons.healing_rounded;
      iconColor = const Color(0xFFD97706);
      iconBg = const Color(0xFFFFFBEB);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: estEnStock ? const Color(0xFF10B981).withValues(alpha: 0.6) : const Color(0xFFE2E8F0),
          width: estEnStock ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: estEnStock
                ? const Color(0xFF10B981).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── EN-TÊTE : ICÔNE + TITRE & DCI + BADGE DISPO / PRIX ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: estEnStock ? const Color(0xFFE6FDF4) : iconBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  estEnStock ? Icons.check_circle_rounded : formeIcon,
                  color: estEnStock ? const Color(0xFF047857) : iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomClean,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dciClean.isNotEmpty && dciClean.toLowerCase() != nomClean.toLowerCase()
                          ? dciClean
                          : (m.dosage.isNotEmpty ? m.dosage : "Médicament essentiel LNME"),
                      style: TextStyle(
                        fontSize: 12,
                        color: estEnStock ? const Color(0xFF047857) : const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (estEnStock && m.prixIndicatif != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF047857), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        m.prixIndicatif!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF047857),
                        ),
                      ),
                      const Text(
                        "En stock",
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: const Text(
                    "LNME TOGO",
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // ── PUCES FORME, DOSAGE & CATÉGORIE NETTOYÉE ──
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (formeClean.isNotEmpty)
                _buildTagChip(formeIcon, formeClean, iconColor, iconBg),
              if (m.dosage.isNotEmpty)
                _buildTagChip(Icons.scale_rounded, m.dosage, const Color(0xFF475569), const Color(0xFFF1F5F9)),
              if (catClean.isNotEmpty)
                _buildTagChip(Icons.bubble_chart_outlined, catClean, const Color(0xFF0D9488), const Color(0xFFF0FDFA)),
            ],
          ),

          const SizedBox(height: 12),

          // ── BANDEAU ÉLÉGANT DE DISPONIBILITÉ (SANS COULEUR D'ALERTE ANXIOGÈNE) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: estEnStock
                  ? (estStockFaible ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4))
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: estEnStock
                    ? (estStockFaible ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0))
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  estEnStock
                      ? (estStockFaible ? Icons.warning_amber_rounded : Icons.verified_rounded)
                      : Icons.phone_in_talk_rounded,
                  size: 14,
                  color: estEnStock
                      ? (estStockFaible ? const Color(0xFFB45309) : const Color(0xFF047857))
                      : const Color(0xFF047857),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    estEnStock
                        ? "Disponible dans ${m.nombrePharmaciesDisponibles} pharmacie${m.nombrePharmaciesDisponibles > 1 ? 's' : ''} à Lomé"
                        : "Disponibilité vérifiable auprès des officines de garde",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: estEnStock
                          ? (estStockFaible ? const Color(0xFF92400E) : const Color(0xFF065F46))
                          : const Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          // ── BOUTONS D'ACTION PRO ──
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (estEnStock) {
                      _afficherModalPharmaciesEnStock(m);
                    } else {
                      _afficherModalContactPharmacies(m);
                    }
                  },
                  icon: Icon(
                    estEnStock ? Icons.storefront_rounded : Icons.call_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  label: Text(
                    estEnStock
                        ? "Voir pharmacies (${m.nombrePharmaciesDisponibles})"
                        : "Contacter pharmacie",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF047857),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () => _afficherFicheMedicament(m),
                  icon: const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF475569)),
                  label: const Text(
                    "Détails",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(IconData icon, String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: textColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
