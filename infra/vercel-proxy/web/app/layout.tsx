import type { ReactNode } from "react";

export const metadata = {
  title: "CrossEngin Chat",
  description: "Vercel-hosted proxy for a self-hosted CrossEngin agent.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui, sans-serif", margin: 0 }}>
        {children}
      </body>
    </html>
  );
}
