from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("ordonnances", "0001_initial")]

    operations = [
        migrations.AddField(
            model_name="ordonnance",
            name="commentaire_pharmacien",
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name="ordonnance",
            name="date_traitement",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="ordonnance",
            name="note_patient",
            field=models.TextField(blank=True),
        ),
    ]
