import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:djim_flutter/services/pharmacie_service.dart';

void main() {
  group('Tests de proximité et tri des pharmacies DjimPharma', () {
    const userLat = 6.1365;
    const userLng = 1.2185;

    double calculerDistance(double? lat, double? lng) {
      if (lat == null || lng == null) return 9999.0;
      final dLat = (lat - userLat) * 111.0;
      final dLng = (lng - userLng) * 111.0 * cos(userLat * pi / 180.0);
      return sqrt(dLat * dLat + dLng * dLng);
    }

    test('Les pharmacies sont triées de la plus proche à la plus éloignée', () {
      final pProche = PharmacieItem(
        id: 1,
        nom: 'Pharmacie de Tokoin (Très Proche)',
        adresse: 'Boulevard Tokoin',
        ville: 'Lomé',
        telephone: '+228 22 21 00 00',
        estDeGarde: true,
        latitude: 6.1370, // ~50 mètres
        longitude: 1.2190,
      );

      final pMoyenne = PharmacieItem(
        id: 2,
        nom: 'Pharmacie Assivito (Centre)',
        adresse: 'Grand Marché',
        ville: 'Lomé',
        telephone: '+228 22 22 00 00',
        estDeGarde: false,
        latitude: 6.1250, // ~1.3 km
        longitude: 1.2220,
      );

      final pEloignee = PharmacieItem(
        id: 3,
        nom: 'Pharmacie de Kara (Loin)',
        adresse: 'Centre Kara',
        ville: 'Kara',
        telephone: '+228 25 50 00 00',
        estDeGarde: true,
        latitude: 9.5511, // ~380 km
        longitude: 1.1861,
      );

      final liste = [pEloignee, pMoyenne, pProche];

      // Tri par proximité
      liste.sort((a, b) {
        final distA = calculerDistance(a.latitude, a.longitude);
        final distB = calculerDistance(b.latitude, b.longitude);
        return distA.compareTo(distB);
      });

      expect(liste[0].id, equals(1)); // pProche en premier
      expect(liste[1].id, equals(2)); // pMoyenne en deuxième
      expect(liste[2].id, equals(3)); // pEloignee en dernier
    });
  });
}
