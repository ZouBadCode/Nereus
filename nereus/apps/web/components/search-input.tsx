"use client"
import * as React from "react"
import { Search } from "lucide-react"
import { Input } from "@workspace/ui/components/input"

export function SearchInput({ placeholder = "Search markets..." }: { placeholder?: string }) {
  const [q, setQ] = React.useState("")
  return (
    <div className="relative w-full max-w-xl">
      <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
      <Input
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder={placeholder}
        className="pl-9 pr-3"
      />
    </div>
  )
}
