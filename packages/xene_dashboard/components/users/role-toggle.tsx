'use server'

import { createAdminClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

async function toggleRole(id: string, newRole: string) {
  'use server'
  const db = createAdminClient()
  await db.from('profiles').update({ role: newRole }).eq('id', id)
  revalidatePath('/dashboard/users')
}

export async function RoleToggle({
  id,
  currentRole,
}: {
  id: string
  currentRole: string
}) {
  const isAdmin = currentRole === 'admin'
  return (
    <form action={toggleRole.bind(null, id, isAdmin ? 'user' : 'admin')}>
      <button
        type="submit"
        className="text-xs px-2 py-1 rounded border border-border hover:bg-accent transition-colors"
      >
        {isAdmin ? 'Remove admin' : 'Make admin'}
      </button>
    </form>
  )
}
