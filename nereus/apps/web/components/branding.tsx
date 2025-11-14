import { Sparkle } from "lucide-react"

export function NereusLogo({ className = "" }: { className?: string }) {
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <Sparkle className="size-5 text-primary" />
      <span className="font-bold tracking-tight">Nereus</span>
    </div>
  )
}
