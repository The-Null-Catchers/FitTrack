"use client";

/**
 * The dashboard's design-system primitives.
 *
 * Deliberately small and hand-rolled rather than pulled from a component
 * library: every surface, radius and colour resolves through the tokens in
 * globals.css, which keeps light and dark mode consistent for free.
 */

import { AlertCircle, Inbox, Loader2, WifiOff } from "lucide-react";
import type { ReactNode } from "react";

import { cn } from "@/lib/utils";

// --- card ------------------------------------------------------------------

export function Card({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <div className={cn("rounded-lg border bg-surface shadow-card", className)}>{children}</div>
  );
}

export function CardHeader({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex items-start justify-between gap-4 border-b px-5 py-4">
      <div>
        <h2 className="text-sm font-semibold">{title}</h2>
        {description ? <p className="mt-0.5 text-sm text-muted">{description}</p> : null}
      </div>
      {action}
    </div>
  );
}

export function CardBody({ className, children }: { className?: string; children: ReactNode }) {
  return <div className={cn("p-5", className)}>{children}</div>;
}

// --- buttons ---------------------------------------------------------------

type ButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost" | "danger";
  size?: "sm" | "md";
  loading?: boolean;
};

export function Button({
  variant = "primary",
  size = "md",
  loading = false,
  className,
  children,
  disabled,
  ...props
}: ButtonProps) {
  return (
    <button
      {...props}
      disabled={disabled || loading}
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded font-medium transition-colors",
        // 44px minimum touch target on the medium size.
        size === "md" ? "h-11 px-4 text-sm" : "h-9 px-3 text-sm",
        "disabled:cursor-not-allowed disabled:opacity-60",
        variant === "primary" && "bg-primary text-primary-foreground hover:bg-primary/90",
        variant === "secondary" && "border bg-surface hover:bg-background",
        variant === "ghost" && "hover:bg-background",
        variant === "danger" && "bg-danger text-white hover:bg-danger/90",
        className,
      )}
    >
      {loading ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> : null}
      {children}
    </button>
  );
}

// --- form controls ---------------------------------------------------------

export function Input({ className, ...props }: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={cn(
        "h-11 w-full rounded border bg-surface px-3 text-sm",
        "placeholder:text-muted focus:border-primary",
        className,
      )}
    />
  );
}

export function Select({
  className,
  children,
  ...props
}: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={cn("h-11 rounded border bg-surface px-3 text-sm focus:border-primary", className)}
    >
      {children}
    </select>
  );
}

export function Field({
  label,
  hint,
  error,
  children,
}: {
  label: string;
  hint?: string;
  error?: string;
  children: ReactNode;
}) {
  return (
    <label className="block space-y-1.5">
      <span className="text-sm font-medium">{label}</span>
      {children}
      {error ? (
        <span className="block text-sm text-danger">{error}</span>
      ) : hint ? (
        <span className="block text-sm text-muted">{hint}</span>
      ) : null}
    </label>
  );
}

// --- badge -----------------------------------------------------------------

const BADGE_TONES = {
  neutral: "bg-border/60 text-foreground",
  success: "bg-success/12 text-success",
  warning: "bg-warning/15 text-warning",
  danger: "bg-danger/12 text-danger",
  info: "bg-info/12 text-info",
  primary: "bg-primary-subtle text-primary",
} as const;

export function Badge({
  tone = "neutral",
  children,
}: {
  tone?: keyof typeof BADGE_TONES;
  children: ReactNode;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium",
        BADGE_TONES[tone],
      )}
    >
      {children}
    </span>
  );
}

// --- state placeholders ----------------------------------------------------

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("skeleton h-4 w-full", className)} aria-hidden />;
}

export function TableSkeleton({ rows = 6, columns = 4 }: { rows?: number; columns?: number }) {
  return (
    <div className="space-y-3 p-5" role="status" aria-label="Loading">
      {Array.from({ length: rows }).map((_, rowIndex) => (
        <div key={rowIndex} className="flex gap-4">
          {Array.from({ length: columns }).map((_, columnIndex) => (
            <Skeleton key={columnIndex} className={columnIndex === 0 ? "w-1/3" : "w-1/6"} />
          ))}
        </div>
      ))}
    </div>
  );
}

export function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 px-6 py-14 text-center">
      <Inbox className="h-8 w-8 text-muted" aria-hidden />
      <p className="font-medium">{title}</p>
      {description ? <p className="max-w-sm text-sm text-muted">{description}</p> : null}
      {action}
    </div>
  );
}

export function ErrorState({
  title = "We couldn't load this",
  description,
  onRetry,
}: {
  title?: string;
  description?: string;
  onRetry?: () => void;
}) {
  const offline = typeof navigator !== "undefined" && !navigator.onLine;
  const Icon = offline ? WifiOff : AlertCircle;
  return (
    <div className="flex flex-col items-center justify-center gap-3 px-6 py-14 text-center">
      <Icon className="h-8 w-8 text-danger" aria-hidden />
      <div>
        <p className="font-medium">{offline ? "You appear to be offline" : title}</p>
        <p className="mt-1 max-w-sm text-sm text-muted">
          {offline
            ? "Check your connection and try again."
            : (description ?? "Please try again in a moment.")}
        </p>
      </div>
      {onRetry ? (
        <Button variant="secondary" size="sm" onClick={onRetry}>
          Try again
        </Button>
      ) : null}
    </div>
  );
}

// --- table -----------------------------------------------------------------

export function Table({ children }: { children: ReactNode }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-sm">{children}</table>
    </div>
  );
}

export function Th({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <th
      scope="col"
      className={cn(
        "border-b px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-muted",
        className,
      )}
    >
      {children}
    </th>
  );
}

export function Td({ children, className }: { children: ReactNode; className?: string }) {
  return <td className={cn("border-b px-5 py-3 align-middle", className)}>{children}</td>;
}

// --- pagination ------------------------------------------------------------

export function Pagination({
  page,
  totalPages,
  total,
  onChange,
}: {
  page: number;
  totalPages: number;
  total: number;
  onChange: (page: number) => void;
}) {
  if (total === 0) return null;
  return (
    <div className="flex items-center justify-between gap-4 px-5 py-3 text-sm">
      <p className="text-muted">
        Page {page} of {totalPages} · {total.toLocaleString()} total
      </p>
      <div className="flex gap-2">
        <Button
          variant="secondary"
          size="sm"
          disabled={page <= 1}
          onClick={() => onChange(page - 1)}
        >
          Previous
        </Button>
        <Button
          variant="secondary"
          size="sm"
          disabled={page >= totalPages}
          onClick={() => onChange(page + 1)}
        >
          Next
        </Button>
      </div>
    </div>
  );
}

// --- metrics ---------------------------------------------------------------

export function StatTile({
  label,
  value,
  hint,
  tone,
}: {
  label: string;
  value: string;
  hint?: string;
  tone?: keyof typeof BADGE_TONES;
}) {
  return (
    <Card className="p-5">
      <p className="text-sm text-muted">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
      {hint ? (
        <p className="mt-1 text-sm">
          {tone ? <Badge tone={tone}>{hint}</Badge> : <span className="text-muted">{hint}</span>}
        </p>
      ) : null}
    </Card>
  );
}
