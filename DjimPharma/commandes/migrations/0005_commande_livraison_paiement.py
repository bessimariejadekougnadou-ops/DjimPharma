import django.db.models.deletion
import uuid

from django.db import migrations, models


def ajouter_references(apps, schema_editor):
    Commande = apps.get_model("commandes", "Commande")
    for commande in Commande.objects.filter(reference__isnull=True):
        commande.reference = uuid.uuid4()
        commande.save(update_fields=["reference"])


class Migration(migrations.Migration):
    dependencies = [
        ("commandes", "0004_commande_adresse_livraison"),
        ("utilisateurs", "0003_utilisateur_roles_et_profils"),
    ]

    operations = [
        migrations.AddField(
            model_name="commande",
            name="livreur",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="commandes",
                to="utilisateurs.livreurprofile",
            ),
        ),
        migrations.AddField(
            model_name="commande",
            name="mode_paiement",
            field=models.CharField(
                choices=[
                    ("paiement_livraison", "Paiement a la livraison"),
                    ("mobile_money", "Mobile money"),
                    ("carte", "Carte bancaire"),
                ],
                default="paiement_livraison",
                max_length=30,
            ),
        ),
        migrations.AddField(
            model_name="commande",
            name="montant_total",
            field=models.DecimalField(decimal_places=2, default=0, max_digits=10),
        ),
        migrations.AddField(
            model_name="commande",
            name="reference",
            field=models.UUIDField(blank=True, editable=False, null=True),
        ),
        migrations.AddField(
            model_name="commande",
            name="statut_paiement",
            field=models.CharField(
                choices=[
                    ("en_attente", "En attente"),
                    ("paye", "Paye"),
                    ("echec", "Echec"),
                ],
                default="en_attente",
                max_length=20,
            ),
        ),
        migrations.RunPython(ajouter_references, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="commande",
            name="reference",
            field=models.UUIDField(default=uuid.uuid4, editable=False, unique=True),
        ),
    ]
