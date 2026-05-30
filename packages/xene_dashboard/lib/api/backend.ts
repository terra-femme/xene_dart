const BASE = process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:8080'

async function backendFetch(path: string, token: string, init?: RequestInit) {
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...init?.headers,
    },
  })
  if (!res.ok) throw new Error(`Backend ${path} → ${res.status}`)
  return res
}

export async function triggerPressScout(token: string) {
  return backendFetch('/press-scout/run', token, { method: 'POST' })
}

export async function pollPublications(token: string, adminSecret: string) {
  return fetch(`${BASE}/admin/poll?force=true`, {
    method: 'POST',
    headers: { 'X-Admin-Secret': adminSecret },
  })
}

export async function getMonitorStats(token: string) {
  const res = await backendFetch('/monitor', token)
  return res.json()
}

export async function refreshPresetSources(slug: string, token: string) {
  return backendFetch(`/presets/templates/${slug}/refresh_all`, token, {
    method: 'POST',
  })
}
