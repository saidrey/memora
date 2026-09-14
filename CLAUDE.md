# Memora — orquestación

Monorepo con tres subproyectos independientes (`memora-backend`, `memora-web`,
`memora-app`) y `specs/` con las especificaciones de Kiro. Detalle de
arquitectura y contrato de API: ver `README.md`.

Cada subproyecto tiene su propio `CLAUDE.md` con las convenciones y errores ya
resueltos en esa capa (dependencias fijadas, patrones de test, reglas de
entorno). Léelo siempre antes de tocar código de ese subproyecto — evita
repetir bugs ya solucionados.

## Flujo de trabajo (spec-driven)

1. **Kiro** especifica en `specs/<subproyecto>/specXX-*.md`.
2. **Yo (sesión principal)** leo la spec + `producto-mvp.md`/`specs/global/`
   si aplica, detecto ambigüedades de producto/arquitectura, y las señalo en
   vez de resolverlas por mi cuenta. Con eso armo un brief corto y preciso
   (qué implementar, contratos, casos de prueba exigidos, qué NO tocar).
3. **Delego la implementación** al agente del subproyecto correspondiente
   (`memora-backend`, `memora-web` o `memora-app`, en `.claude/agents/`) vía
   Agent tool, pasándole el brief. El agente trabaja únicamente dentro de su
   carpeta.
4. **Reviso el diff y los resultados de build/test** del agente antes de
   darlo por bueno — incluyendo la actualización que haya hecho a su propio
   `CLAUDE.md`/`AGENTS.md` (cada agente documenta ahí, como parte de su
   tarea, cualquier gotcha/patrón/pin nuevo que descubra; reviso que no
   duplique ni contradiga lo ya escrito).
5. Reporto al usuario: qué se implementó, cómo verificarlo, y qué queda
   marcado para revisión de Kiro.

## Reglas que aplican a todo el monorepo

- Nunca editar `specs/` para marcar checklists — el avance se documenta en el
  `README.md` de cada subproyecto (precedente establecido con Kiro).
- Nunca modificar ningún `.npmrc`, ni ejecutar `npm install -g` ni cambiar
  configuración global de npm/Node/Flutter/Dart.
- Un agente/tarea de un subproyecto no toca los otros dos subproyectos ni
  `specs/`.
- Ante contradicción, ambigüedad, o algo que toque producto/arquitectura: no
  resolverlo en silencio — describirlo, explicar la causa, proponer opción y
  marcarlo para revisión de Kiro.
