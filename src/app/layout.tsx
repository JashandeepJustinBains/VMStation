import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'VMStation Repository Explorer',
  description: 'Interactive repository visualization for VMStation Kubernetes deployment project',
  keywords: ['kubernetes', 'repository', 'visualization', 'cluster', 'vmstation'],
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="water-surface">
        {children}
      </body>
    </html>
  );
}