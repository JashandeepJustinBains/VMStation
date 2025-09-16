import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'VMStation Repository Explorer',
  description: 'Interactive visualization of VMStation Kubernetes infrastructure repository',
  keywords: ['kubernetes', 'infrastructure', 'visualization', 'repository', 'cluster'],
  authors: [{ name: 'VMStation' }],
  openGraph: {
    title: 'VMStation Repository Explorer',
    description: 'Interactive visualization of VMStation Kubernetes infrastructure',
    type: 'website',
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>
        <div id="root">{children}</div>
      </body>
    </html>
  )
}