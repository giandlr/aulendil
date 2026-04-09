#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────
# Scaffold Next.js / React frontend
#
# Called by bootstrap.sh when FRONTEND_FRAMEWORK=next
# Creates the same directory structure as the Nuxt scaffold
# but with React/Next.js conventions.
# ─────────────────────────────────────────────────────

echo "  Creating Next.js frontend..."
mkdir -p frontend

# package.json
cat > frontend/package.json << 'PKGEOF'
{
  "name": "frontend",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui"
  },
  "dependencies": {
    "next": "^15.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  }
}
PKGEOF

# next.config.ts
cat > frontend/next.config.ts << 'NEXTEOF'
import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  // Strict mode for catching React issues early
  reactStrictMode: true,
}

export default nextConfig
NEXTEOF

# tsconfig.json
cat > frontend/tsconfig.json << 'TSCEOF'
{
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": {
      "@/*": ["./*"]
    }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
TSCEOF

# Directories
for dir in components hooks stores services types tests app; do
    mkdir -p "frontend/$dir"
done
mkdir -p frontend/app/\(auth\)/login
mkdir -p frontend/app/\(app\)

# globals.css with Tailwind
mkdir -p frontend/app
cat > frontend/app/globals.css << 'CSSEOF'
@import "tailwindcss";
CSSEOF

# tailwind.config.ts
cat > frontend/tailwind.config.ts << 'TWEOF'
import type { Config } from 'tailwindcss'

const config: Config = {
  content: [
    './app/**/*.{ts,tsx}',
    './components/**/*.{ts,tsx}',
    './hooks/**/*.{ts,tsx}',
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}

export default config
TWEOF

# postcss.config.mjs
cat > frontend/postcss.config.mjs << 'PCEOF'
const config = {
  plugins: {
    "@tailwindcss/postcss": {},
  },
};
export default config;
PCEOF

# Root layout
cat > frontend/app/layout.tsx << 'TSXEOF'
import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Aulendil',
  description: 'Built with Aulendil',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-gray-950 text-gray-100">
        <nav className="sticky top-0 z-50 border-b border-gray-800 bg-gray-950/80 backdrop-blur-sm">
          <div className="flex items-center justify-between max-w-7xl mx-auto px-6 h-14">
            <a href="/" className="text-lg font-semibold text-white">
              Aulendil
            </a>
            <div className="flex items-center gap-4">
              <a href="/" className="text-sm text-gray-400 hover:text-gray-200">
                Home
              </a>
            </div>
          </div>
        </nav>
        <main className="max-w-7xl mx-auto px-6 py-8">
          {children}
        </main>
      </body>
    </html>
  )
}
TSXEOF

# Home page
cat > frontend/app/page.tsx << 'TSXEOF'
export default function Home() {
  return (
    <div className="text-center py-20">
      <h1 className="text-4xl font-bold text-gray-100 mb-4">
        Welcome to Your App
      </h1>
      <p className="text-lg text-gray-400">
        Start building by describing what you want to Claude Code.
      </p>
    </div>
  )
}
TSXEOF

# Loading state
cat > frontend/app/loading.tsx << 'TSXEOF'
export default function Loading() {
  return (
    <div className="flex items-center justify-center py-20">
      <div className="h-8 w-8 animate-spin rounded-full border-4 border-gray-600 border-t-white" />
    </div>
  )
}
TSXEOF

# Error boundary
cat > frontend/app/error.tsx << 'TSXEOF'
'use client'

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  return (
    <div className="text-center py-20">
      <h2 className="text-2xl font-bold text-red-400 mb-4">Something went wrong</h2>
      <p className="text-gray-400 mb-6">
        {error.message || 'An unexpected error occurred.'}
      </p>
      <button
        onClick={reset}
        className="rounded-md bg-blue-600 px-4 py-2 text-white hover:bg-blue-700"
      >
        Try again
      </button>
    </div>
  )
}
TSXEOF

# Not found page
cat > frontend/app/not-found.tsx << 'TSXEOF'
export default function NotFound() {
  return (
    <div className="text-center py-20">
      <h2 className="text-2xl font-bold text-gray-100 mb-4">Page not found</h2>
      <p className="text-gray-400 mb-6">The page you are looking for does not exist.</p>
      <a
        href="/"
        className="rounded-md bg-blue-600 px-4 py-2 text-white hover:bg-blue-700"
      >
        Go home
      </a>
    </div>
  )
}
TSXEOF

# Supabase service client
cat > frontend/services/supabase.ts << 'TSEOF'
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
TSEOF

echo "  Created frontend/ (Next.js + React)"
