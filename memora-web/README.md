# Memora Web

MVP web de Memora con Next.js App Router y lenguaje visual Aurora light-first.

## Incluye

- Login Google Identity Services con code client, `drive.file` y sesión Memora persistida en `localStorage`.
- Refresh automático ante 401 y logout.
- Dashboard de álbumes propios/colaborativos, creación y detalle.
- Fotos con bytes descargados directamente desde Google Drive usando el token efímero del backend.
- Colaboradores, invitaciones y enlace de compartición.
- Visor público sin login en `/s/[token]` y aceptación de invitaciones en `/invite/[token]`.

Toda llamada al backend pasa por `src/lib/api/`. La única excepción es la descarga de bytes desde `googleapis.com`, encapsulada en `src/lib/api/drive.ts`.

## Configuración

```bash
cp .env.example .env.local
# Configura NEXT_PUBLIC_GOOGLE_CLIENT_ID y NEXT_PUBLIC_API_BASE_URL
PORT=3001 npm run dev
```

En Google Cloud Console, configura el origen autorizado de la web y habilita los scopes `openid email profile drive.file`. El Web Client ID es configuración pública, no un secreto.

## Verificación

```bash
npm run lint
npm run build
```

El backend local corre por defecto en `http://localhost:3000`; la web usa `PORT=3001` para evitar la colisión.
