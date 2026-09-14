# Memora — Fuente de verdad funcional del MVP

Este documento captura las **decisiones de producto** aprobadas por el Founder/PO. Es la referencia funcional del MVP: define **qué** hace Memora, no cómo se implementa. Las specs técnicas deben respetarlo.

## Principio central

> **Memora preserva y organiza recuerdos, pero las fotografías siguen siendo propiedad de sus usuarios. Memora es el facilitador, no el custodio.**

- Las fotografías permanecen en los Google Drive de sus propietarios.
- Memora mantiene referencias y relaciones (álbum ↔ fotografía ↔ usuario).
- Memora no almacena copias de las fotografías en el MVP.
- Memora no elimina fotografías del Drive de un usuario sin una decisión explícita futura.
- En álbumes compartidos, cada colaborador conserva sus propias fotografías en su Drive.
- El propietario puede crear copias de fotos de colaboradores en su biblioteca mediante "Guardar en mi biblioteca".

## Modelo de datos funcional

- **Una fotografía pertenece a un único usuario** (su propietario) y es un único archivo en su Drive.
- **Una fotografía puede pertenecer a múltiples álbumes** — sin duplicar el archivo en Drive. Memora mantiene la relación N:M foto ↔ álbum.
- **Un álbum** tiene un owner y puede reunir fotografías físicamente almacenadas en varios Drives (multi-Drive).

```
User
 └── Photo (1 archivo en su Drive)
       ├── Album A
       ├── Album B
       └── Album C
```

## Decisiones aprobadas

- **D1 — Permisos de colaboradores (opción B).** Dos roles: **Owner** (administra álbum y colaboradores) y **Collaborator** (visualiza todas las fotos del álbum y aporta las suyas). Sin roles configurables en el MVP.
- **D2 — Visibilidad (opción A).** El visor es accesible por cualquiera con el enlace (aplica a enlace/QR/NFC). No indexable ni descubrible públicamente. La gestión/modificación requiere autenticación.
- **D3 — Usuario elimina su propia foto (opción A).** Se elimina solo la relación foto↔álbum. El archivo permanece en el Drive del propietario. Memora nunca borra del Drive automáticamente.
- **D4 — Owner quita foto de un colaborador (opción A).** Solo elimina la relación foto↔álbum. No toca el archivo ni la propiedad del colaborador.
- **D5 — Colaborador abandona el álbum.** Deja de ser colaborador y de poder aportar. Sus fotos **permanecen** en el álbum mientras sigan disponibles (no desaparecen automáticamente) y siguen siendo suyas. El owner puede "Guardar en mi biblioteca" para conservarlas como copia. Si el colaborador luego borra su original de Drive, aplica la política de "archivo no disponible" (D9).
- **D6 — Adoptar / "Guardar en mi biblioteca" (opción A).** En el MVP solo el **owner del álbum** puede copiar una foto de un colaborador a su propia biblioteca. Es una **copia** al Drive del owner (no transferencia de propiedad); el original del colaborador queda intacto; la copia sobrevive aunque el colaborador se vaya o borre su original. **⏸️ DIFERIDA A POST-MVP (decisión del PO, 2026-09-14):** con el scope `drive.file` fijado, la copia cross-Drive no es viable de forma transparente sin romper decisiones técnicas aprobadas (ver `memora-backend/spec06-adoptar.md`). En el MVP **no** hay "Guardar en mi biblioteca"; las fotos de colaboradores se ven **mientras estén disponibles en su Drive** (D5 + D9). D6 se retomará cuando el PO lo decida (posible cambio de scope/infra).
- **D7 — Móvil y Web (ambas con gestión).**
  - **App Flutter (captura + gestión completa):** login, autorización Drive, crear álbum, ver/abrir álbumes, seleccionar/optimizar/subir fotos, visualizar, compartir, colaboradores, gestión de fotos, NFC/QR.
  - **Web Next.js:** **Visor** (acceso enlace/NFC/QR, visualización, navegación, responsive) + **Plataforma autenticada** (login, ver álbumes propios, crear/gestionar álbumes, compartir, gestionar colaboradores, gestión básica de fotos).
  - No se exige paridad 100% entre plataformas. Diferencias de distribución concretas se consultan al PO.
- **D8 — Metadatos de foto (mínimos).** id Memora, `fileId` de Drive, propietario, relaciones con álbumes, fecha de incorporación a Memora, fecha de captura (si disponible), dimensiones, tipo/formato, tamaño, orden dentro del álbum, estado de disponibilidad. **NO se almacena geolocalización GPS/EXIF** (privacidad).
- **D9 — Cambios directos en Drive (verificación perezosa, opción A).** No hay sync activa (ni polling ni webhooks) en el MVP. Al mostrar una foto, Memora verifica disponibilidad. Si el archivo fue eliminado / está en papelera / inaccesible / sin permisos → se marca **"no disponible"** y no se muestra como disponible. Renombrar o mover NO rompe la referencia (se usa el `fileId` estable, nunca ruta/nombre). Si vuelve a estar disponible, se puede revalidar/recuperar.
- **D10 — Autorización de Drive revocada (opción A).** La cuenta Memora permanece activa; no hay logout forzado. Cuando una operación requiera Drive y falte autorización, se pide **re-autorizar Drive**. Álbumes y referencias permanecen.
- **D11 — Biblioteca personal (opción A, precisada).** Existe una Biblioteca personal que contiene **solo las fotos que Memora conoce/incorpora** (NO todo el Drive del usuario). Los álbumes son agrupaciones sobre esas fotos. Foto y álbum son entidades independientes con relación **muchos-a-muchos**.
- **D12 — Invitación de colaboradores (opción A).** Solo **enlace de invitación** en el MVP (sin código). Flujo: Owner invita → Memora genera enlace → invitado abre → Google Login → acepta → pasa a Collaborator.
- **D13 — Invitaciones expiran y son revocables (opción A).** El Owner puede revocar; las invitaciones expiran; una invitación revocada/expirada no sirve para unirse. Valor de expiración: lo define Tech Lead (se consulta al PO si tiene impacto de UX).
- **D14 — NFC/QR (opción A).** El usuario crea el álbum y luego le asocia NFC y/o QR. Sin etiquetas pre-fabricadas/no reclamadas ni marketplace en el MVP. Resuelven vía URL estable de Memora.
- **D15 — Optimización automática (opción A).** Optimización automática con buenos defaults; el usuario no elige calidad/resolución. Parámetros técnicos definidos por Tech Lead (equilibrio calidad/tamaño/velocidad/almacenamiento/UX).
- **D16 — Eliminar un álbum.** Elimina el álbum y sus relaciones foto↔álbum. **No** borra fotos de ningún Drive, ni de colaboradores, ni de la Biblioteca personal del usuario. Una foto en otros álbumes sigue en ellos. Una copia "Guardada en mi biblioteca" persiste. Resumen: **eliminar un álbum elimina la agrupación, no las fotografías.**

## Precisiones adicionales (aprobadas)

- **Estructura de Drive (revisada):** NO habrá una carpeta física por álbum. La estructura de Memora en Drive es **principalmente organizativa** (p. ej. una carpeta única de Memora por usuario). Los álbumes son entidades **lógicas** de Memora; una foto puede pertenecer a varios álbumes sin duplicarse físicamente. (Reemplaza la idea de "una carpeta por álbum" del documento inicial.)
- **M5 Adopción:** la viabilidad de `drive.file` y el mecanismo de copia cross-Drive se validaron en la spec de M5 (`memora-backend/spec06-adoptar.md`). **Resultado (2026-09-14): NO viable de forma transparente con `drive.file`; M5 diferida a post-MVP** por decisión del PO. Confirmado que con `drive.file` el Drive del owner no puede leer el archivo del colaborador (da 404), y el backend no maneja bytes por diseño. En el MVP las fotos de colaboradores se muestran mientras estén disponibles en su Drive; no hay copia. Se retomará con una eventual decisión de scope/infra.
- **M9 Web:** la web es parte del MVP. "En pausa" es solo prioridad de desarrollo, no exclusión funcional.

## Roles (resumen)

| Rol | Puede |
|---|---|
| **Owner** | Administrar álbum, invitar/administrar colaboradores, aportar fotos, quitar cualquier foto del álbum (relación), "Guardar en mi biblioteca" fotos de colaboradores |
| **Collaborator** | Ver todas las fotos del álbum, aportar sus propias fotos, quitar/abandonar sus propias aportaciones |
