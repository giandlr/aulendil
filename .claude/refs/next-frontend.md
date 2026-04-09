# Next.js / React — Detailed Reference

Read this file before writing Next.js code. For quick rules, see `.claude/rules/next-frontend.md`.

---

## App Router File Conventions

```
frontend/
├── app/
│   ├── layout.tsx          # Root layout (wraps all pages)
│   ├── page.tsx            # Home page (/)
│   ├── loading.tsx         # Root loading state
│   ├── error.tsx           # Root error boundary
│   ├── not-found.tsx       # 404 page
│   ├── (auth)/
│   │   ├── login/page.tsx
│   │   └── register/page.tsx
│   └── (app)/
│       ├── layout.tsx      # Authenticated layout
│       ├── dashboard/page.tsx
│       └── settings/page.tsx
├── components/             # Shared React components
├── hooks/                  # Custom React hooks
├── stores/                 # Zustand stores
├── services/               # ALL Supabase client calls
├── types/                  # Shared TypeScript types
├── tests/                  # Vitest + Playwright tests
└── middleware.ts           # Auth redirect guard
```

---

## Root Layout Example

```tsx
// frontend/app/layout.tsx
import type { Metadata } from 'next'
import './globals.css'
import { AuthProvider } from '@/components/auth-provider'

export const metadata: Metadata = {
  title: 'My App',
  description: 'Built with Aulendil',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body>
        <AuthProvider>
          {children}
        </AuthProvider>
      </body>
    </html>
  )
}
```

---

## Zustand Store Example

```tsx
// frontend/stores/auth-store.ts
import { create } from 'zustand'
import type { User, Session } from '@supabase/supabase-js'

interface AuthState {
  user: User | null
  session: Session | null
  loading: boolean
  setSession: (session: Session | null) => void
  setUser: (user: User | null) => void
  setLoading: (loading: boolean) => void
  clear: () => void
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  session: null,
  loading: true,
  setSession: (session) => set({ session, user: session?.user ?? null }),
  setUser: (user) => set({ user }),
  setLoading: (loading) => set({ loading }),
  clear: () => set({ user: null, session: null, loading: false }),
}))
```

---

## React Hook Form + Zod Example

```tsx
// frontend/components/create-task-form.tsx
'use client'

import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const taskSchema = z.object({
  title: z.string().min(1, 'Title is required').max(200),
  description: z.string().max(2000).optional(),
  priority: z.enum(['low', 'medium', 'high']),
})

type TaskFormData = z.infer<typeof taskSchema>

export function CreateTaskForm({ onSubmit }: { onSubmit: (data: TaskFormData) => Promise<void> }) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<TaskFormData>({
    resolver: zodResolver(taskSchema),
    defaultValues: { priority: 'medium' },
  })

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
      <div>
        <label htmlFor="title" className="block text-sm font-medium">
          Title
        </label>
        <input
          id="title"
          {...register('title')}
          className="mt-1 block w-full rounded-md border px-3 py-2"
        />
        {errors.title && (
          <p className="mt-1 text-sm text-red-600">{errors.title.message}</p>
        )}
      </div>

      <div>
        <label htmlFor="description" className="block text-sm font-medium">
          Description
        </label>
        <textarea
          id="description"
          {...register('description')}
          className="mt-1 block w-full rounded-md border px-3 py-2"
          rows={3}
        />
      </div>

      <div>
        <label htmlFor="priority" className="block text-sm font-medium">
          Priority
        </label>
        <select
          id="priority"
          {...register('priority')}
          className="mt-1 block w-full rounded-md border px-3 py-2"
        >
          <option value="low">Low</option>
          <option value="medium">Medium</option>
          <option value="high">High</option>
        </select>
      </div>

      <button
        type="submit"
        disabled={isSubmitting}
        className="rounded-md bg-blue-600 px-4 py-2 text-white hover:bg-blue-700 disabled:opacity-50"
      >
        {isSubmitting ? 'Creating...' : 'Create Task'}
      </button>
    </form>
  )
}
```

---

## Service Layer with Supabase

```tsx
// frontend/services/supabase.ts
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
```

```tsx
// frontend/services/tasks.ts
import { supabase } from './supabase'

export interface Task {
  id: string
  title: string
  description: string | null
  priority: 'low' | 'medium' | 'high'
  created_at: string
  updated_at: string
}

export async function getTasks(cursor?: string, limit = 20) {
  let query = supabase
    .from('tasks')
    .select('id, title, description, priority, created_at, updated_at')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
    .limit(limit)

  if (cursor) {
    query = query.lt('created_at', cursor)
  }

  const { data, error } = await query
  if (error) throw error
  return data as Task[]
}

export async function createTask(task: { title: string; description?: string; priority: string }) {
  const { data, error } = await supabase
    .from('tasks')
    .insert(task)
    .select('id, title, description, priority, created_at, updated_at')
    .single()

  if (error) throw error
  return data as Task
}
```

---

## useAuth Hook

```tsx
// frontend/hooks/use-auth.ts
'use client'

import { useEffect } from 'react'
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/services/supabase'

export function useAuth() {
  const { user, session, loading, setSession, setLoading, clear } = useAuthStore()

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session)
      setLoading(false)
    })

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        setSession(session)
      }
    )

    return () => subscription.unsubscribe()
  }, [setSession, setLoading])

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
  }

  const signOut = async () => {
    await supabase.auth.signOut()
    clear()
  }

  return { user, session, loading, signIn, signOut }
}
```

---

## Auth Middleware

```tsx
// frontend/middleware.ts
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const publicPaths = ['/login', '/register', '/forgot-password']

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  // Allow public paths
  if (publicPaths.some((path) => pathname.startsWith(path))) {
    return NextResponse.next()
  }

  // Check for session token in cookies
  const token = request.cookies.get('sb-access-token')?.value
  if (!token) {
    return NextResponse.redirect(new URL('/login', request.url))
  }

  return NextResponse.next()
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|api).*)'],
}
```

---

## AuthProvider Component

```tsx
// frontend/components/auth-provider.tsx
'use client'

import { useAuth } from '@/hooks/use-auth'

export function AuthProvider({ children }: { children: React.ReactNode }) {
  // Initialize auth listener on mount
  useAuth()
  return <>{children}</>
}
```

---

## Testing Patterns

### Vitest + @testing-library/react

```tsx
// frontend/tests/components/create-task-form.test.tsx
import { describe, it, expect, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CreateTaskForm } from '@/components/create-task-form'

describe('CreateTaskForm', () => {
  it('validates required title', async () => {
    const onSubmit = vi.fn()
    render(<CreateTaskForm onSubmit={onSubmit} />)

    await userEvent.click(screen.getByRole('button', { name: /create task/i }))

    await waitFor(() => {
      expect(screen.getByText(/title is required/i)).toBeInTheDocument()
    })
    expect(onSubmit).not.toHaveBeenCalled()
  })

  it('submits valid form data', async () => {
    const onSubmit = vi.fn().mockResolvedValue(undefined)
    render(<CreateTaskForm onSubmit={onSubmit} />)

    await userEvent.type(screen.getByLabelText(/title/i), 'My task')
    await userEvent.click(screen.getByRole('button', { name: /create task/i }))

    await waitFor(() => {
      expect(onSubmit).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'My task', priority: 'medium' })
      )
    })
  })
})
```

### Vitest Config

```ts
// frontend/vitest.config.ts
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'happy-dom',
    globals: true,
    setupFiles: ['./tests/setup.ts'],
    include: ['tests/**/*.test.{ts,tsx}', '**/*.test.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json-summary'],
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '.'),
    },
  },
})
```

```ts
// frontend/tests/setup.ts
import '@testing-library/jest-dom/vitest'
```

### Playwright E2E

Playwright configuration and test patterns are identical to Nuxt projects. The same `tests/e2e/` directory structure applies.

---

## Environment Variables

| Variable | Prefix | Description |
|----------|--------|-------------|
| `NEXT_PUBLIC_SUPABASE_URL` | `NEXT_PUBLIC_` | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `NEXT_PUBLIC_` | Public API key (respects RLS) |
| `NEXT_PUBLIC_API_BASE_URL` | `NEXT_PUBLIC_` | FastAPI backend base URL |
| `SUPABASE_SERVICE_ROLE_KEY` | (none — server only) | Admin key — NEVER expose to client |

---

## Key Differences from Nuxt/Vue

| Concern | Nuxt/Vue | Next.js/React |
|---------|----------|---------------|
| State | Pinia stores | Zustand stores |
| Forms | vee-validate + zod | React Hook Form + @hookform/resolvers + zod |
| Routing | `pages/` file-based | `app/` directory (App Router) |
| Components | `<script setup lang="ts">` SFC | Function components + TypeScript |
| Composables | `composables/` | `hooks/` (custom React hooks) |
| Auth guard | Nuxt route middleware | `middleware.ts` (Next.js edge) |
| Type check | `vue-tsc --noEmit` | `tsc --noEmit` |
| Env prefix | `NUXT_PUBLIC_` | `NEXT_PUBLIC_` |
| Loading state | Nuxt `<Suspense>` | `loading.tsx` file convention |
| Error state | Nuxt error.vue | `error.tsx` file convention |
