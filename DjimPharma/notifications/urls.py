from django.urls import path
from .views import (
    LireNotificationAPIView,
    ListeNotificationsAPIView,
    PreferencesGardeAPIView,
)

urlpatterns = [
    path("notifications/", ListeNotificationsAPIView.as_view(), name="liste_notifications"),
    path("notifications/<int:pk>/lire/", LireNotificationAPIView.as_view(), name="lire_notification"),
    path("notifications/preferences-garde/", PreferencesGardeAPIView.as_view(), name="preferences_garde"),
]
