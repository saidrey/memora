import { getHealth } from "@/lib/api/health";

type BackendStatus =
  | { connected: true; status: string }
  | { connected: false; message: string };

async function checkBackendConnectivity(): Promise<BackendStatus> {
  try {
    const health = await getHealth();
    return { connected: true, status: health.status };
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Error desconocido";
    return { connected: false, message };
  }
}

// Minimal connectivity view for memora-web/spec01-fundacion-web.md — not a
// designed screen. Visual identity is a separate, still-pending decision.
export default async function Home() {
  const backend = await checkBackendConnectivity();

  return (
    <div className="flex flex-1 items-center justify-center bg-zinc-50 font-sans dark:bg-black">
      <main className="flex w-full max-w-md flex-col items-center gap-4 rounded-2xl border border-black/[.08] bg-white p-10 text-center dark:border-white/[.145] dark:bg-black">
        <h1 className="text-xl font-semibold text-zinc-950 dark:text-zinc-50">
          Memora
        </h1>
        <div className="flex items-center gap-2">
          <span
            aria-hidden
            className={`h-2.5 w-2.5 rounded-full ${
              backend.connected ? "bg-emerald-500" : "bg-red-500"
            }`}
          />
          <p className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
            Backend: {backend.connected ? "ok" : "no disponible"}
          </p>
        </div>
        {!backend.connected && (
          <p className="max-w-xs text-xs text-zinc-500 dark:text-zinc-500">
            {backend.message}
          </p>
        )}
      </main>
    </div>
  );
}
