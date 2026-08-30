'use client'

import { useEffect } from 'react'

export const REFERRAL_STORAGE_KEY = 'cande-referral-code'

export function ReferralCapture() {
  useEffect(() => {
    const code = new URLSearchParams(window.location.search).get('ref')?.trim().toUpperCase()
    if (code && /^[A-Z0-9_-]{5,40}$/.test(code)) localStorage.setItem(REFERRAL_STORAGE_KEY, code)
  }, [])
  return null
}
