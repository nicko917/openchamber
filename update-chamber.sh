#!/bin/bash
set -e  # Salir ante cualquier error

# ============================================================
# CONFIGURACIÓN (¡AJUSTA ESTAS VARIABLES SEGÚN TU ENTORNO!)
# ============================================================
REPO_DIR="/root/apps/openchamber"
COMPOSE_DIR="/root/apps/openchamber"          # Si el compose está en otro sitio, cámbialo
BRANCH="dokploy-fixes"                        # Tu rama de trabajo
UPSTREAM_URL="https://github.com/openchamber/openchamber.git"   # ¡VERIFICA ESTA URL!
UPSTREAM_BRANCH="main"                        # main o master (comprueba en el original)
COMPOSE_FILE="docker-compose.yml"             # Nombre de tu archivo compose
# ============================================================

echo "=== Actualizando OpenChamber desde upstream ==="

# 1. Ir al directorio del repositorio
cd "$REPO_DIR" || { echo "ERROR: No existe $REPO_DIR"; exit 1; }

# 2. Asegurar que estamos en la rama correcta
git checkout "$BRANCH" || { echo "ERROR: No se pudo cambiar a rama $BRANCH"; exit 1; }

# 3. Configurar upstream si no existe
if ! git remote get-url upstream >/dev/null 2>&1; then
    echo "Añadiendo upstream: $UPSTREAM_URL"
    git remote add upstream "$UPSTREAM_URL"
else
    echo "Upstream ya configurado."
fi

# 4. Guardar cambios locales no commitados (si los hay)
if ! git diff --quiet; then
    echo "Hay cambios locales sin commit. Guardándolos con stash..."
    git stash push -m "stash automático antes de actualizar"
    STASHED=true
else
    STASHED=false
fi

# 5. Traer cambios del upstream
echo "Obteniendo cambios de upstream..."
git fetch upstream

# 6. Fusionar la rama upstream en nuestra rama
echo "Fusionando upstream/$UPSTREAM_BRANCH en $BRANCH..."
if git merge upstream/"$UPSTREAM_BRANCH"; then
    echo "Fusión exitosa (sin conflictos)."
else
    echo "ERROR: Conflictos detectados. Resuélvelos manualmente y luego continúa."
    echo "Comandos para resolver:"
    echo "  # Edita los archivos conflictivos (especialmente Dockerfile)"
    echo "  git add ."
    echo "  git commit -m 'Resuelve conflictos'"
    echo "  git push origin $BRANCH"
    echo "  docker compose -f $COMPOSE_DIR/$COMPOSE_FILE build --pull && docker compose -f $COMPOSE_DIR/$COMPOSE_FILE up -d"
    exit 1
fi

# 7. Recuperar stash (si existía) y manejar conflictos
if [ "$STASHED" = true ]; then
    echo "Recuperando cambios guardados en stash..."
    if ! git stash pop; then
        echo "ERROR: Hubo conflictos al aplicar el stash. Resuélvelos manualmente y luego continúa."
        echo "  git add ."
        echo "  git commit -m 'Aplica stash'"
        echo "  git push origin $BRANCH"
        echo "  docker compose -f $COMPOSE_DIR/$COMPOSE_FILE build --pull && docker compose -f $COMPOSE_DIR/$COMPOSE_FILE up -d"
        exit 1
    fi
fi

# 8. Subir cambios a tu fork en GitHub
echo "Subiendo cambios a origin/$BRANCH..."
if git push origin "$BRANCH"; then
    echo "Push exitoso."
else
    echo "El push fue rechazado (posible divergencia)."
    read -p "¿Quieres forzar el push? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        git push origin "$BRANCH" --force
    else
        echo "Operación cancelada. Debes subir los cambios manualmente."
        exit 1
    fi
fi

# 9. Reconstruir el contenedor con Docker
echo "Reconstruyendo contenedor..."
cd "$COMPOSE_DIR" || { echo "ERROR: No existe $COMPOSE_DIR"; exit 1; }
docker compose -f "$COMPOSE_FILE" build --pull
docker compose -f "$COMPOSE_FILE" up -d

echo "=== Actualización completada ==="
