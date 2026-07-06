#!/usr/bin/env bash
# sync-analogizer.sh
# Sincroniza la rama 'analogizer' con los cambios del repo original (upstream/master),
# manteniendo 'master' como espejo limpio.
#
# Uso: ./sync-analogizer.sh
#
# Requiere que el remoto 'upstream' ya esté configurado:
#   git remote add upstream https://github.com/drizzt/openfpga-SMS.git

set -e  # aborta ante cualquier error no controlado

WORK_BRANCH="analogizer"
MAIN_BRANCH="master"
UPSTREAM_REMOTE="upstream"
ORIGIN_REMOTE="origin"

echo "== Sync ${WORK_BRANCH} <- ${UPSTREAM_REMOTE}/${MAIN_BRANCH} =="

# 1. Comprobar que el remoto upstream existe
if ! git remote get-url "${UPSTREAM_REMOTE}" >/dev/null 2>&1; then
    echo "ERROR: no existe el remoto '${UPSTREAM_REMOTE}'."
    echo "Ejecuta primero: git remote add ${UPSTREAM_REMOTE} https://github.com/drizzt/openfpga-SMS.git"
    exit 1
fi

# 2. Comprobar que no hay un merge/rebase a medias de una sesión anterior
if [ -f .git/MERGE_HEAD ] || [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
    echo "ERROR: hay un merge o rebase sin terminar de una sesión anterior."
    echo "Resuélvelo antes de continuar (git status para ver el estado)."
    exit 1
fi

# 3. Comprobar que no hay cambios sin commitear en ninguna rama
if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: tienes cambios sin commitear. Comitéalos o guárdalos antes de sincronizar:"
    echo
    git status --short
    echo
    echo "Sugerencia: git add -A && git commit -m 'wip'"
    exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
echo "Rama actual antes de empezar: ${CURRENT_BRANCH}"

# 4. Actualizar master como espejo limpio
echo
echo "-- Actualizando ${MAIN_BRANCH} desde ${UPSTREAM_REMOTE} --"
git checkout "${MAIN_BRANCH}"
git fetch "${UPSTREAM_REMOTE}"

if ! git merge --ff-only "${UPSTREAM_REMOTE}/${MAIN_BRANCH}"; then
    echo "ERROR: ${MAIN_BRANCH} no se pudo actualizar con fast-forward."
    echo "Esto normalmente significa que ${MAIN_BRANCH} tiene commits propios que no deberían estar ahí."
    echo "Revisa manualmente con: git log ${MAIN_BRANCH}..${UPSTREAM_REMOTE}/${MAIN_BRANCH}"
    exit 1
fi

git push "${ORIGIN_REMOTE}" "${MAIN_BRANCH}"
echo "-- ${MAIN_BRANCH} actualizado y subido a ${ORIGIN_REMOTE} --"

# 5. Traer los cambios a la rama de trabajo
echo
echo "-- Integrando ${MAIN_BRANCH} en ${WORK_BRANCH} --"
git checkout "${WORK_BRANCH}"

if git merge "${MAIN_BRANCH}"; then
    echo
    echo "-- Merge sin conflictos. Subiendo a ${ORIGIN_REMOTE}/${WORK_BRANCH} --"
    git push "${ORIGIN_REMOTE}" "${WORK_BRANCH}"
    echo
    echo "== Sincronización completada sin incidencias =="
else
    echo
    echo "== ATENCION: hay conflictos que resolver a mano =="
    echo "1. Revisa los ficheros en conflicto:"
    echo "     git status"
    echo "2. Edita cada fichero, busca las marcas <<<<<<< ======= >>>>>>>"
    echo "3. Marca como resuelto:"
    echo "     git add <fichero>"
    echo "4. Cierra el merge:"
    echo "     git commit"
    echo "5. Sube los cambios:"
    echo "     git push ${ORIGIN_REMOTE} ${WORK_BRANCH}"
    echo
    echo "El script se detiene aquí para que resuelvas manualmente."
    exit 1
fi