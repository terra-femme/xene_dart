'use server'

import { createAdminClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

async function togglePublication(id: string, enabled: boolean) {
  'use server'
  const db = createAdminClient()
  await db.from('press_publications').update({ enabled }).eq('id', id)
  revalidatePath('/dashboard/publications')
}

export async function PublicationToggles({
  id,
  enabled,
}: {
  id: string
  enabled: boolean
}) {
  return (
    <form action={togglePublication.bind(null, id, !enabled)}>
      <button
        type="submit"
        className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${
          enabled ? 'bg-emerald-500' : 'bg-muted'
        }`}
      >
        <span
          className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white transition-transform ${
            enabled ? 'translate-x-4' : 'translate-x-1'
          }`}
        />
      </button>
    </form>
  )
}
