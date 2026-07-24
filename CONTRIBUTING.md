# Workflow de contribución · Slay Flutter

## Convención de ramas

Cada corrección / feature va en una **rama paralela a `main`** y se valida
antes de mergear. No usamos Pull Requests — los merges son locales
(`git merge --no-ff`) una vez que la corrección está probada en el celu
o desktop.

### Tipos de rama

| Prefijo | Uso | Ejemplo |
|---|---|---|
| `fix/` | Bugfix puntual | `fix/offline-mode-no-funciona` |
| `feat/` | Feature nueva | `feat/pomodoro-improvements` |
| `chore/` | Mantenimiento / refactor | `chore/migrate-drift-schema-v3` |
| `docs/` | Sólo documentación | `docs/update-readme-troubleshooting` |

### Flujo

```bash
# 1. Asegurarse de estar en main actualizado
git checkout main
git pull

# 2. Crear rama desde main
git checkout -b fix/<descripcion>

# 3. Hacer cambios, probar en el celu (./run.sh android) o desktop
flutter analyze
./run.sh android

# 4. Commit atómico, mensaje en imperativo y sin firma
git add -p
git commit -m "fix: ..."

# 5. Validar que no rompe nada
flutter test            # tests unitarios
flutter build apk       # build Android (sin errores)

# 6. Si todo OK → merge a main sin PR
git checkout main
git merge --no-ff fix/<descripcion>   # preserva el historial
git push

# 7. Borrar la rama local
git branch -d fix/<descripcion>
```

### Mensajes de commit

- Imperativo, presente: "fix: ..." no "fixed ..." ni "fixes ..."
- Sin firma de autor (Claude Code, GPT, etc.)
- Sin emoji
- Primera línea ≤ 72 chars
- Cuerpo opcional con bullets explicando el "qué" y el "por qué"

Ejemplos:
```
fix: hidratar cache local para arrancar app sin red
feat: agregar drag-to-reorder en lista de tareas
chore: subir AGP a 8.2.1 para compatibilidad con JDK 21
```

### ¿Por qué sin PRs?

Es una app personal de un solo maintainer. Los PRs agregan fricción
sin valor (no hay code review de un equipo). La "revisión" la hace el
celu Android real (validación end-to-end) + `flutter analyze` + tests
unitarios.

### ¿Cuándo sí abrir un PR?

Si en el futuro hay colaboradores externos, sí. Mientras tanto, el
flujo es rama → validar → merge a main.
