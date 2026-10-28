import type { Metadata } from "next";
import "./globals.css";
import { AuthProvider } from "@/components/auth-provider";

export const metadata: Metadata = {
  title: "Memora · tus recuerdos, más cerca",
  description: "Álbumes digitales para compartir lo que importa.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="es" className="h-full antialiased">
      <body className="min-h-full"><AuthProvider>{children}</AuthProvider></body>
    </html>
  );
}
