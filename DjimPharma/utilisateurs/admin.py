from django.contrib import admin

from .models import LivreurProfile, PharmacienProfile, Utilisateur

admin.site.register(Utilisateur)
admin.site.register(PharmacienProfile)
admin.site.register(LivreurProfile)
