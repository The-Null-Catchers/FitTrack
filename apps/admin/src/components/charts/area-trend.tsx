"use client";

import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import type { MetricPoint } from "@/lib/api";

/**
 * A single-series trend. Colours come from the theme variables so the chart is
 * legible in both light and dark mode without a second palette.
 */
export function AreaTrend({
  data,
  label,
  color = "hsl(var(--primary))",
}: {
  data: MetricPoint[];
  label: string;
  color?: string;
}) {
  const gradientId = `gradient-${label.replace(/\s+/g, "-").toLowerCase()}`;

  return (
    <ResponsiveContainer width="100%" height={220}>
      <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -20 }}>
        <defs>
          <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.28} />
            <stop offset="100%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
        <XAxis
          dataKey="day"
          tickLine={false}
          axisLine={false}
          tick={{ fill: "hsl(var(--muted))", fontSize: 11 }}
          tickFormatter={(value: string) =>
            new Date(value).toLocaleDateString("en", { month: "short", day: "numeric" })
          }
          minTickGap={24}
        />
        <YAxis
          tickLine={false}
          axisLine={false}
          allowDecimals={false}
          tick={{ fill: "hsl(var(--muted))", fontSize: 11 }}
          width={44}
        />
        <Tooltip
          contentStyle={{
            background: "hsl(var(--surface-raised))",
            border: "1px solid hsl(var(--border))",
            borderRadius: 10,
            fontSize: 12,
            color: "hsl(var(--foreground))",
          }}
          labelFormatter={(value: string) =>
            new Date(value).toLocaleDateString("en", {
              weekday: "short",
              month: "short",
              day: "numeric",
            })
          }
          formatter={(value: number) => [value, label]}
        />
        <Area
          type="monotone"
          dataKey="value"
          name={label}
          stroke={color}
          strokeWidth={2}
          fill={`url(#${gradientId})`}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
