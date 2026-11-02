from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("pharmacies", "0001_initial")]

    operations = [
        migrations.AddField(
            model_name="pharmacie",
            name="est_active",
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name="pharmacie",
            name="latitude",
            field=models.FloatField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="pharmacie",
            name="longitude",
            field=models.FloatField(blank=True, null=True),
        ),
    ]
