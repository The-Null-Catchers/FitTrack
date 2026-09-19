"use client";

import {
  Activity,
  Bot,
  Dumbbell,
  HardDrive,
  LayoutDashboard,
  ListChecks,
  LogOut,
  ScrollText,
  Users,
} from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";

import { ThemeToggle } from "@/components/theme-toggle";
import { Button } from "@/components/ui";
import { useAuth } from "@/hooks/use-auth";
import { cn } from "@/lib/utils";

const NAVIGATION = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/users", label: "Users", icon: Users },
  { href: "/exercises", label: "Exercises", icon: Dumbbell },
  { href: "/templates", label: "Templates", icon: ListChecks },
  { href: "/ai-usage", label: "AI usage", icon: Bot },
  { href: "/storage", label: "Storage", icon: HardDrive },
  { href: "/system", label: "System health", icon: Activity },
  { href: "/audit-logs", label: "Audit log", icon: ScrollText },
];

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { user, loading, signOut } = useAuth();
  const pathname = usePathname();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !user) router.replace("/login");
  }, [user, loading, router]);

  if (loading || !user) {
    return (
      <main className="grid min-h-screen place-items-center">
        <p className="text-sm text-muted">Checking your session…</p>
      </main>
    );
  }

  return (
    <div className="flex min-h-screen">
      <aside className="hidden w-60 shrink-0 border-r bg-surface lg:flex lg:flex-col">
        <div className="flex items-center gap-2 border-b px-5 py-4">
          <span className="grid h-8 w-8 place-items-center rounded bg-primary text-primary-foreground">
            <Dumbbell className="h-4 w-4" aria-hidden />
          </span>
          <span className="font-semibold">FitTrack</span>
        </div>

        <nav className="flex-1 space-y-0.5 p-3" aria-label="Main">
          {NAVIGATION.map(({ href, label, icon: Icon }) => {
            const active = pathname === href || pathname.startsWith(`${href}/`);
            return (
              <Link
                key={href}
                href={href}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "flex items-center gap-3 rounded px-3 py-2 text-sm transition-colors",
                  active
                    ? "bg-primary-subtle font-medium text-primary"
                    : "text-muted hover:bg-background hover:text-foreground",
                )}
              >
                <Icon className="h-4 w-4" aria-hidden />
                {label}
              </Link>
            );
          })}
        </nav>

        <div className="border-t p-3">
          <p className="truncate px-3 text-sm font-medium">{user.full_name}</p>
          <p className="truncate px-3 text-xs text-muted">{user.email}</p>
          <Button variant="ghost" size="sm" className="mt-2 w-full justify-start" onClick={signOut}>
            <LogOut className="h-4 w-4" aria-hidden />
            Sign out
          </Button>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between gap-4 border-b bg-surface px-5 py-3">
          {/* Compact navigation for narrow screens. */}
          <nav className="flex gap-1 overflow-x-auto lg:hidden" aria-label="Main">
            {NAVIGATION.map(({ href, label, icon: Icon }) => {
              const active = pathname === href || pathname.startsWith(`${href}/`);
              return (
                <Link
                  key={href}
                  href={href}
                  aria-label={label}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "grid h-10 w-10 shrink-0 place-items-center rounded",
                    active ? "bg-primary-subtle text-primary" : "text-muted",
                  )}
                >
                  <Icon className="h-4 w-4" aria-hidden />
                </Link>
              );
            })}
          </nav>
          <div className="hidden lg:block" />
          <ThemeToggle />
        </header>

        <main className="flex-1 space-y-6 p-5 lg:p-8">{children}</main>
      </div>
    </div>
  );
}
