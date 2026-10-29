import type { Metadata } from 'next';
import { Sora } from 'next/font/google';

import './globals.css';

/**
 * Sora is the only font family in the product (see the design system). It is
 * self-hosted at build time by next/font, so the panel has no runtime
 * dependency on Google Fonts.
 */
const sora = Sora({
  subsets: ['latin'],
  weight: ['400', '500', '600'],
  variable: '--font-sora',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'Temi Finance Admin',
  description: 'Operations console for a Temi Finance deployment.',
  robots: { index: false, follow: false },
};

/**
 * Applies the persisted theme before first paint so a dark-mode operator never
 * sees a light flash. Runs inline, ahead of hydration.
 */
const themeScript = `
(function () {
  try {
    var stored = localStorage.getItem('mm-admin-theme');
    var dark = stored ? stored === 'dark'
      : window.matchMedia('(prefers-color-scheme: dark)').matches;
    if (dark) document.documentElement.classList.add('dark');
  } catch (_) {}
})();
`;

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={sora.variable} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
