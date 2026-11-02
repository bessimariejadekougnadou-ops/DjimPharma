from rest_framework import serializers
from .models import HistoriqueGarde, PeriodeGarde, Pharmacie


class PeriodeGardeSerializer(serializers.ModelSerializer):
    pharmacie_nom = serializers.ReadOnlyField(source="pharmacie.nom")
    pharmacie_ville = serializers.ReadOnlyField(source="pharmacie.ville")
    pharmacie_telephone = serializers.ReadOnlyField(source="pharmacie.telephone")
    pharmacie_adresse = serializers.ReadOnlyField(source="pharmacie.adresse")
    valide_par_nom = serializers.SerializerMethodField()
    est_active = serializers.SerializerMethodField()

    class Meta:
        model = PeriodeGarde
        fields = [
            "id",
            "pharmacie",
            "pharmacie_nom",
            "pharmacie_ville",
            "pharmacie_adresse",
            "pharmacie_telephone",
            "date_debut",
            "date_fin",
            "zone",
            "source",
            "date_verification",
            "statut_validation",
            "valide_par",
            "valide_par_nom",
            "commentaire",
            "est_active",
            "date_creation",
        ]

    def get_valide_par_nom(self, obj):
        if obj.valide_par:
            return obj.valide_par.get_full_name() or obj.valide_par.username
        return None

    def get_est_active(self, obj):
        return obj.est_active()


class PharmacieSerializer(serializers.ModelSerializer):
    periode_garde = serializers.SerializerMethodField()

    class Meta:
        model = Pharmacie
        fields = [
            "id",
            "nom",
            "adresse",
            "ville",
            "quartier",
            "telephone",
            "est_de_garde",
            "latitude",
            "longitude",
            "google_place_id",
            "source_donnees",
            "statut_verification",
            "source_verification",
            "date_derniere_synchro",
            "periode_garde",
        ]

    def get_periode_garde(self, obj):
        active = obj.periode_garde_active()
        if not active:
            return None
        return {
            "id": active.id,
            "date_debut": active.date_debut,
            "date_fin": active.date_fin,
            "zone": active.zone,
            "source": active.source,
            "date_verification": active.date_verification,
            "statut_validation": active.statut_validation,
        }


class PublicationGardeSerializer(serializers.ModelSerializer):
    class Meta:
        model = PeriodeGarde
        fields = [
            "pharmacie",
            "date_debut",
            "date_fin",
            "zone",
            "source",
            "commentaire",
        ]

    def validate(self, attrs):
        debut = attrs.get("date_debut")
        fin = attrs.get("date_fin")
        if debut and fin and fin <= debut:
            raise serializers.ValidationError({"date_fin": "La date de fin doit être postérieure à la date de début."})
        return attrs


class HistoriqueGardeSerializer(serializers.ModelSerializer):
    modifie_par_nom = serializers.SerializerMethodField()
    pharmacie_nom = serializers.ReadOnlyField(source="pharmacie.nom")

    class Meta:
        model = HistoriqueGarde
        fields = [
            "id",
            "pharmacie",
            "pharmacie_nom",
            "action",
            "modifie_par_nom",
            "details",
            "date_action",
        ]

    def get_modifie_par_nom(self, obj):
        if obj.modifie_par:
            return obj.modifie_par.get_full_name() or obj.modifie_par.username
        return "Système DjimPharma"
