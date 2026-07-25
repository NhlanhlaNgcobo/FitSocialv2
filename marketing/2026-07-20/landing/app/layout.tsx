import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "FitSocial | Train. Fuel. Share. Grow.",
  description: "A South African fitness community for training consistently, fuelling your goals, and growing together.",
  openGraph: {
    title: "FitSocial | Built for South Africa",
    description: "Train, fuel, share, and grow with your community.",
    images: ["/og.png"],
  },
  twitter: { card: "summary_large_image", images: ["/og.png"] },
  icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en-ZA"><body>{children}</body></html>;
}
