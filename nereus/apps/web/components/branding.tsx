import { Sparkle } from "lucide-react"

export function NereusLogo({ className = "" }: { className?: string }) {
  return (
    <div className={`flex items-center gap-2 ${className}`}>
          <img src="./nereus_logo.png" alt="Nereus Logo" className="h-10 w-10 cursor-pointer" />

      <span className="font-bold tracking-tight">Nereus</span>
    </div>
  )
}
