from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.db import transaction
from rest_framework import serializers

from .models import EmailVerificationToken, HistoriqueMotDePasse, SessionUtilisateur, Utilisateur


class InscriptionSerializer(serializers.Serializer):
    nom = serializers.CharField(max_length=100)
    prenom = serializers.CharField(max_length=100)
    email = serializers.EmailField()
    mot_de_passe = serializers.CharField(write_only=True, min_length=8)
    telephone = serializers.CharField(max_length=20, required=False, allow_blank=True)
    adresse_principale = serializers.CharField(
        max_length=255, required=False, allow_blank=True
    )
    ville = serializers.CharField(max_length=100, required=False, allow_blank=True)
    quartier = serializers.CharField(max_length=100, required=False, allow_blank=True)
    langue_preferee = serializers.CharField(max_length=10, required=False, default="fr")

    def validate_email(self, valeur):
        email = valeur.lower().strip()

        if User.objects.filter(username=email).exists():
            raise serializers.ValidationError("Un compte utilise deja cet email.")

        if Utilisateur.objects.filter(email=email).exists():
            raise serializers.ValidationError("Un utilisateur utilise deja cet email.")

        return email

    @transaction.atomic
    def create(self, donnees):
        mot_de_passe = donnees.pop("mot_de_passe")
        email = donnees["email"]

        compte = User.objects.create_user(
            username=email,
            email=email,
            password=mot_de_passe,
            first_name=donnees["prenom"],
            last_name=donnees["nom"],
        )

        return Utilisateur.objects.create(compte=compte, role="client", **donnees)


class ProfilUtilisateurSerializer(serializers.ModelSerializer):
    class Meta:
        model = Utilisateur
        fields = [
            "id",
            "nom",
            "prenom",
            "email",
            "role",
            "telephone",
            "adresse_principale",
            "ville",
            "quartier",
            "langue_preferee",
            "est_actif",
        ]
        read_only_fields = ["email", "role"]


class ConnexionSerializer(serializers.Serializer):
    email = serializers.CharField()
    mot_de_passe = serializers.CharField(write_only=True)

    def validate(self, donnees):
        identifiant = donnees["email"].lower().strip()
        user_obj = (
            User.objects.filter(email__iexact=identifiant).first()
            or User.objects.filter(username__iexact=identifiant).first()
        )
        if user_obj:
            compte = authenticate(username=user_obj.username, password=donnees["mot_de_passe"])
        else:
            compte = authenticate(username=identifiant, password=donnees["mot_de_passe"])

        if compte is None:
            raise serializers.ValidationError("Email ou mot de passe incorrect.")

        if not (
            hasattr(compte, "profil")
            or hasattr(compte, "profil_pharmacien")
            or hasattr(compte, "profil_livreur")
        ):
            from .models import Utilisateur
            role = "admin" if (compte.is_superuser or compte.is_staff) else "client"
            domain = "djimpharma.local"
            profil, _ = Utilisateur.objects.get_or_create(
                email=compte.email or f"{compte.username}@{domain}",
                defaults={
                    "compte": compte,
                    "nom": compte.last_name or compte.username,
                    "prenom": compte.first_name or "Utilisateur",
                    "role": role,
                },
            )
            if profil.compte != compte:
                profil.compte = compte
                profil.save()

        donnees["compte"] = compte
        return donnees
class ChangementMotDePasseSerializer(serializers.Serializer):
    ancien_mot_de_passe = serializers.CharField(write_only=True)
    nouveau_mot_de_passe = serializers.CharField(write_only=True, min_length=8)

    def validate_ancien_mot_de_passe(self, value):
        user = self.context["request"].user
        if not user.check_password(value):
            raise serializers.ValidationError("L'ancien mot de passe est incorrect.")
        return value

    def validate(self, donnees):
        if donnees["ancien_mot_de_passe"] == donnees["nouveau_mot_de_passe"]:
            raise serializers.ValidationError(
                "Le nouveau mot de passe doit être différent de l'ancien."
            )
        return donnees


class SessionUtilisateurSerializer(serializers.ModelSerializer):
    class Meta:
        model = SessionUtilisateur
        fields = [
            "id",
            "device_name",
            "ip_address",
            "user_agent",
            "statut",
            "date_connexion",
            "date_derniere_activite",
            "date_deconnexion",
        ]


class EmailVerificationTokenSerializer(serializers.ModelSerializer):
    class Meta:
        model = EmailVerificationToken
        fields = ["id", "code", "date_expiration", "est_utilise"]
