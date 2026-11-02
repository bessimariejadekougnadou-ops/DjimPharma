from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("notifications", "0001_initial")]

    operations = [
        migrations.AddField(
            model_name="notification",
            name="canal",
            field=models.CharField(
                choices=[
                    ("application", "Application"),
                    ("email", "Email"),
                    ("sms", "SMS"),
                ],
                default="application",
                max_length=20,
            ),
        ),
    ]
