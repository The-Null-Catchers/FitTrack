"use client";

import { useQuery } from "@tanstack/react-query";
import { CheckCircle2, CircleAlert, CircleHelp } from "lucide-react";

import { Card, CardBody, CardHeader, ErrorState, Skeleton } from "@/components/ui";
import { api, type SystemHealth } from "@/lib/api";
import { formatDateTime } from "@/lib/utils";

const COMPONENTS: [keyof SystemHealth, string, string][] = [
  ["api", "API", "Serving HTTP requests"],
  ["database", "PostgreSQL", "Primary datastore"],
  ["redis", "Redis", "Rate limiting, cache and job queue"],
  ["storage", "Object storage", "Avatars, exercise media, progress photos"],
  ["worker", "Worker", "Reminders, summaries and cleanup"],
];

function StatusIcon({ status }: { status: string }) {
  if (status === "ok") return <CheckCircle2 className="h-5 w-5 text-success" aria-hidden />;
  if (status === "unavailable") return <CircleAlert className="h-5 w-5 text-danger" aria-hidden />;
  return <CircleHelp className="h-5 w-5 text-warning" aria-hidden />;
}

export default function SystemPage() {
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["admin", "health"],
    queryFn: () => api.get<SystemHealth>("/api/v1/admin/health"),
    refetchInterval: 30_000,
  });

  if (isError) {
    return (
      <Card>
        <ErrorState title="We couldn't reach the health endpoint" onRetry={() => refetch()} />
      </Card>
    );
  }

  return (
    <>
      <header>
        <h1 className="text-xl font-semibold">System health</h1>
        <p className="text-sm text-muted">Live status of each platform dependency.</p>
      </header>

      <Card>
        <CardHeader
          title="Components"
          description={
            data ? `Checked ${formatDateTime(data.checked_at)}` : "Checking dependencies…"
          }
        />
        <CardBody className="divide-y p-0">
          {isLoading || !data
            ? Array.from({ length: 5 }).map((_, index) => (
                <div key={index} className="px-5 py-4">
                  <Skeleton className="w-40" />
                </div>
              ))
            : COMPONENTS.map(([key, label, description]) => (
                <div key={key} className="flex items-center gap-4 px-5 py-4">
                  <StatusIcon status={String(data[key])} />
                  <div className="flex-1">
                    <p className="font-medium">{label}</p>
                    <p className="text-sm text-muted">{description}</p>
                  </div>
                  <span className="text-sm tabular-nums text-muted">{String(data[key])}</span>
                </div>
              ))}
        </CardBody>
      </Card>

      {data ? (
        <Card>
          <CardHeader title="Runtime" />
          <CardBody className="space-y-1.5 text-sm">
            <div className="flex justify-between border-b py-1.5">
              <span className="text-muted">Environment</span>
              <span>{data.environment}</span>
            </div>
            <div className="flex justify-between border-b py-1.5">
              <span className="text-muted">Service</span>
              <span>{data.version}</span>
            </div>
            <div className="flex justify-between py-1.5">
              <span className="text-muted">Uptime</span>
              <span className="tabular-nums">
                {Math.floor(data.uptime_seconds / 3600)}h{" "}
                {Math.floor((data.uptime_seconds % 3600) / 60)}m
              </span>
            </div>
          </CardBody>
        </Card>
      ) : null}
    </>
  );
}
