from django.urls import path

from .views import (
    AuditEtapeDetailAPIView,
    AuditEtapeListAPIView,
    AuditProgressAPIView,
    AuditSessionDetailAPIView,
    AuditSessionListAPIView,
)

urlpatterns = [
    path("audit/etapes/", AuditEtapeListAPIView.as_view(), name="audit-etapes-list"),
    path("audit/etapes/<int:pk>/", AuditEtapeDetailAPIView.as_view(), name="audit-etapes-detail"),
    path("audit/sessions/", AuditSessionListAPIView.as_view(), name="audit-sessions-list"),
    path("audit/sessions/<int:pk>/", AuditSessionDetailAPIView.as_view(), name="audit-sessions-detail"),
    path("audit/progression/", AuditProgressAPIView.as_view(), name="audit-progression"),
]
