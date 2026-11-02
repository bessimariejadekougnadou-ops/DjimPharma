from rest_framework import generics, status
from rest_framework.response import Response

from .models import AuditEtape, AuditSession
from .serializers import AuditEtapeSerializer, AuditSessionSerializer


class AuditEtapeListAPIView(generics.ListCreateAPIView):
    queryset = AuditEtape.objects.all()
    serializer_class = AuditEtapeSerializer


class AuditEtapeDetailAPIView(generics.RetrieveUpdateDestroyAPIView):
    queryset = AuditEtape.objects.all()
    serializer_class = AuditEtapeSerializer


class AuditSessionListAPIView(generics.ListCreateAPIView):
    queryset = AuditSession.objects.all()
    serializer_class = AuditSessionSerializer


class AuditSessionDetailAPIView(generics.RetrieveUpdateDestroyAPIView):
    queryset = AuditSession.objects.all()
    serializer_class = AuditSessionSerializer


class AuditProgressAPIView(generics.GenericAPIView):
    """Retourne un résumé rapide d’avancement des étapes d’audit."""

    def get(self, request):
        etapes = AuditEtape.objects.all()
        total = etapes.count()
        valide = etapes.filter(statut="valide").count()
        en_cours = etapes.filter(statut="en_cours").count()
        bloque = etapes.filter(statut="bloque").count()
        a_faire = etapes.filter(statut="a_faire").count()

        progression = 0 if total == 0 else round((valide / total) * 100, 2)

        return Response(
            {
                "total_etapes": total,
                "valide": valide,
                "en_cours": en_cours,
                "bloque": bloque,
                "a_faire": a_faire,
                "progression_pourcentage": progression,
            },
            status=status.HTTP_200_OK,
        )
