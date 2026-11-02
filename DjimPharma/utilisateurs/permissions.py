from rest_framework.permissions import BasePermission


class IsClient(BasePermission):
    message = "Un compte client est requis."

    def has_permission(self, request, view):
        return bool(
            request.user.is_authenticated
            and hasattr(request.user, "profil")
            and request.user.profil.role == "client"
        )


class IsPharmacien(BasePermission):
    message = "Un compte pharmacien lie a une pharmacie est requis."

    def has_permission(self, request, view):
        return bool(request.user.is_authenticated and hasattr(request.user, "profil_pharmacien"))


class IsLivreur(BasePermission):
    message = "Un compte livreur est requis."

    def has_permission(self, request, view):
        return bool(request.user.is_authenticated and hasattr(request.user, "profil_livreur"))
