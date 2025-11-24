"use client"
import * as React from "react"

type Props = {
  points?: number
  width?: number
  height?: number
  stroke?: string
  className?: string
}

export function Sparkline({ points = 24, width = 220, height = 64, stroke = "hsl(var(--chart-2))", className = "" }: Props) {
  const path = React.useMemo(() => {
    const rand = (seed: number) => {
      const x = Math.sin(seed) * 10000
      return x - Math.floor(x)
    }
    const data = Array.from({ length: points }, (_, i) => rand(i + 1))
    const max = Math.max(...data)
    const min = Math.min(...data)
    const scaleY = (v: number) => height - ((v - min) / (max - min + 1e-6)) * height
    const step = width / (points - 1)
    return data.map((v, i) => `${i === 0 ? "M" : "L"}${i * step},${scaleY(v)}`).join(" ")
  }, [points, width, height])

  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} className={className} aria-hidden>
      <path d={path} fill="none" stroke={stroke} strokeWidth={2} />
    </svg>
  )
}
