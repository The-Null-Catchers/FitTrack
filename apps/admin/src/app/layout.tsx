import type { Metadata } from "next";

import { AuthProvider } from "@/hooks/use-auth";
import { Providers } from "@/components/providers";

import "./globals.css";

export const metadata: Metadata = {
  title: "FitTrack Admin",
  description: "Operations dashboard for the FitTrack platform",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        {/*
          Apply the stored theme before first paint so a dark-mode user never
          sees a white flash.
        */}
        <script
          dangerouslySetInnerHTML={{
            __html: `(function(){try{var t=localStorage.getItem("fittrack.admin.theme")||"system";var d=t==="dark"||(t==="system"&&matchMedia("(prefers-color-scheme: dark)").matches);document.documentElement.classList.toggle("dark",d);}catch(e){}})();`,
          }}
        />
      </head>
      <body className="min-h-screen">
        <Providers>
          <AuthProvider>{children}</AuthProvider>
        </Providers>
      </body>
    </html>
  );
}
