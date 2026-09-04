import { ReferralProgram } from '@/components/referral-program'
import { StrawberryLedger } from '@/components/strawberry-ledger'

export default function RewardsLayout({ children }: { children: React.ReactNode }) {
  return <>{children}<StrawberryLedger/><aside className="page max-w-4xl !pt-0"><ReferralProgram compact /></aside></>
}
