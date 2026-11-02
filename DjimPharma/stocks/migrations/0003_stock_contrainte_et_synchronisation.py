from django.db import migrations, models
from django.utils import timezone


class Migration(migrations.Migration):
    dependencies = [("stocks", "0002_stockpharmacie_quantite")]

    operations = [
        migrations.AddField(
            model_name="stockpharmacie",
            name="derniere_synchronisation",
            field=models.DateTimeField(auto_now=True, default=timezone.now),
            preserve_default=False,
        ),
        migrations.AddConstraint(
            model_name="stockpharmacie",
            constraint=models.UniqueConstraint(
                fields=("pharmacie", "medicament"),
                name="stock_unique_par_pharmacie_et_medicament",
            ),
        ),
    ]
