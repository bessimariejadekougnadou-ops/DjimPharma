from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("medicaments", "0002_remove_medicament_prix")]

    operations = [
        migrations.AddField(
            model_name="medicament",
            name="code_dci",
            field=models.CharField(blank=True, max_length=100),
        ),
        migrations.AddField(
            model_name="medicament",
            name="est_essentiel",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="medicament",
            name="forme_dosage",
            field=models.CharField(blank=True, max_length=100),
        ),
    ]
