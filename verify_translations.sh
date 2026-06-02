#!/bin/bash
# Script to verify all heroine translations are present

echo "=== Verificando Traducciones de Heroínas ==="
echo ""

TRANSLATIONS=(
    "LOBBY_HERO_GENDER"
    "LOBBY_HERO_RANDOM"
    "LOBBY_HERO_MALE"
    "LOBBY_HERO_FEMALE"
    "HERO_DACIL_ABILITY"
    "HERO_DACIL_ABILITY_DESC"
    "HERO_GUAYARMINA_ABILITY"
    "HERO_GUAYARMINA_ABILITY_DESC"
    "HERO_TIBIABIN_ABILITY"
    "HERO_TIBIABIN_ABILITY_DESC"
    "HERO_CATALINA_ABILITY"
    "HERO_CATALINA_ABILITY_DESC"
    "HERO_GRACE_ABILITY"
    "HERO_GRACE_ABILITY_DESC"
    "HERO_DULCINEA_ABILITY"
    "HERO_DULCINEA_ABILITY_DESC"
    "HERO_CLEITO_ABILITY"
    "HERO_CLEITO_ABILITY_DESC"
    "HERO_ELISSA_ABILITY"
    "HERO_ELISSA_ABILITY_DESC"
)

CSV_FILE="project/assets/translations/translations.csv"

missing=0
for key in "${TRANSLATIONS[@]}"; do
    if grep -q "^$key," "$CSV_FILE"; then
        echo "✅ $key"
    else
        echo "❌ FALTA: $key"
        missing=$((missing + 1))
    fi
done

echo ""
echo "=== Resumen ==="
echo "Total de claves verificadas: ${#TRANSLATIONS[@]}"
echo "Faltantes: $missing"

if [ $missing -eq 0 ]; then
    echo ""
    echo "✅ ¡Todas las traducciones están en el CSV!"
    echo ""
    echo "📋 Próximos pasos:"
    echo "1. Cierra Godot completamente"
    echo "2. Vuelve a abrir el proyecto"
    echo "3. Espera a que termine la importación (barra de progreso)"
    echo "4. Verifica el lobby"
    echo ""
    echo "Si aún no ves las traducciones:"
    echo "- Godot → FileSystem → assets/translations/translations.csv"
    echo "- Click derecho → Reimport"
    echo "- Reinicia Godot"
else
    echo ""
    echo "❌ Faltan traducciones. Ejecuta el script de adición."
fi
