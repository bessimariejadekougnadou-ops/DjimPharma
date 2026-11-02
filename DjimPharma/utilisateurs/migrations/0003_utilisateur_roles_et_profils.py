import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("pharmacies", "0001_initial"),
        ("utilisateurs", "0002_utilisateur_compte"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name="utilisateur",
            name="adresse_principale",
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name="utilisateur",
            name="langue_preferee",
            field=models.CharField(default="fr", max_length=10),
        ),
        migrations.AddField(
            model_name="utilisateur",
            name="role",
            field=models.CharField(
                choices=[
                    ("client", "Client"),
                    ("pharmacien", "Pharmacien"),
                    ("livreur", "Livreur"),
                ],
                default="client",
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name="utilisateur",
            name="telephone",
            field=models.CharField(blank=True, max_length=20),
        ),
        migrations.CreateModel(
            name="LivreurProfile",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("telephone", models.CharField(blank=True, max_length=20)),
                (
                    "immatriculation_vehicule",
                    models.CharField(blank=True, max_length=50),
                ),
                ("est_disponible", models.BooleanField(default=True)),
                (
                    "statut_actuel",
                    models.CharField(
                        choices=[
                            ("disponible", "Disponible"),
                            ("en_livraison", "En livraison"),
                            ("indisponible", "Indisponible"),
                        ],
                        default="disponible",
                        max_length=20,
                    ),
                ),
                (
                    "compte",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="profil_livreur",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
        ),
        migrations.CreateModel(
            name="PharmacienProfile",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("telephone", models.CharField(blank=True, max_length=20)),
                (
                    "compte",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="profil_pharmacien",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "pharmacie",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="pharmaciens",
                        to="pharmacies.pharmacie",
                    ),
                ),
            ],
        ),
    ]
