import { ReferralProgram } from '@/components/referral-program'

export default function RewardsLayout({ children }: { children: React.ReactNode }) {
  return <>{children}<aside className="page max-w-4xl !pt-0"><ReferralProgram compact /></aside></>
}
