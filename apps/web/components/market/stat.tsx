export function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between text-xs text-muted-foreground">
      <span>{label}</span>
      <span className="ml-4 font-semibold text-foreground">{value}</span>
    </div>
  )
}
