import { createBrowserClient } from '@supabase/ssr'
const publishableKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
export const isSupabaseConfigured=Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL&&publishableKey)
export const supabase=isSupabaseConfigured?createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,publishableKey!):null
