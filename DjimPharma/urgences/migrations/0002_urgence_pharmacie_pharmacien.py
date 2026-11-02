import django.db.models.deletion

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("pharmacies", "0001_initial"),
        ("urgences", "0001_initial"),
        ("utilisateurs", "0003_utilisateur_roles_et_profils"),
    ]

    operations = [
        migrations.AddField(
            model_name="demandeurgence",
            name="pharmacie",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="urgences",
                to="pharmacies.pharmacie",
            ),
        ),
        migrations.AddField(
            model_name="demandeurgence",
            name="pharmacien",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="urgences",
                to="utilisateurs.pharmacienprofile",
            ),
        ),
    ]
