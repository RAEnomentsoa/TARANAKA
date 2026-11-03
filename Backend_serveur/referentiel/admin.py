from django.contrib import admin

from .models import CSB, Province, ReferenceOms, Region, TypeDangerGrossesse


@admin.register(Province)
class ProvinceAdmin(admin.ModelAdmin):
    list_display = ("nom",)
    search_fields = ("nom",)


@admin.register(Region)
class RegionAdmin(admin.ModelAdmin):
    list_display = ("nom", "province")
    list_filter = ("province",)
    search_fields = ("nom", "province__nom")
    list_select_related = ("province",)


@admin.register(CSB)
class CSBAdmin(admin.ModelAdmin):
    list_display = ("name", "region", "tel")
    list_filter = ("region",)
    search_fields = ("name", "tel", "region__nom")
    list_select_related = ("region",)


@admin.register(TypeDangerGrossesse)
class TypeDangerGrossesseAdmin(admin.ModelAdmin):
    list_display = ("description",)
    search_fields = ("description",)


@admin.register(ReferenceOms)
class ReferenceOmsAdmin(admin.ModelAdmin):
    list_display = (
        "indicateur",
        "sexe",
        "cle",
        "valeur_l",
        "valeur_m",
        "valeur_s",
        "mesure_type",
    )
    list_filter = ("indicateur", "sexe", "mesure_type")
    search_fields = ("indicateur", "cle")
