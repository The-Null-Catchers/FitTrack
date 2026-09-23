"use client";

import { useQuery } from "@tanstack/react-query";

import { AreaTrend } from "@/components/charts/area-trend";
import { Card, CardBody, CardHeader, ErrorState, Skeleton, StatTile } from "@/components/ui";
import { api, type Overview } from "@/lib/api";
import { formatBytes, formatNumber } from "@/lib/utils";

export default function DashboardPage() {
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["admin", "overview"],
    queryFn: () => api.get<Overview>("/api/v1/admin/overview"),
  });

  if (isError) {
    return (
      <Card>
        <ErrorState
          title="We couldn't load the dashboard"
          description="The metrics service didn't respond."
          onRetry={() => refetch()}
        />
      </Card>
    );
  }

  return (
    <>
      <header>
        <h1 className="text-xl font-semibold">Dashboard</h1>
        <p className="text-sm text-muted">Platform activity across FitTrack.</p>
      </header>

      {isLoading || !data ? (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {Array.from({ length: 8 }).map((_, index) => (
            <Card key={index} className="p-5">
              <Skeleton className="w-24" />
              <Skeleton className="mt-3 h-7 w-16" />
            </Card>
          ))}
        </div>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatTile
              label="Total users"
              value={formatNumber(data.total_users)}
              hint={`+${formatNumber(data.new_registrations_7d)} in 7 days`}
              tone="success"
            />
            <StatTile
              label="Active users (7d)"
              value={formatNumber(data.active_users_7d)}
              hint={`${formatNumber(data.active_users_30d)} in 30 days`}
            />
            <StatTile
              label="Workouts completed"
              value={formatNumber(data.workouts_completed_total)}
              hint={`${formatNumber(data.workouts_completed_7d)} this week`}
            />
            <StatTile
              label="AI requests (7d)"
              value={formatNumber(data.ai_requests_7d)}
              hint={`${formatNumber(data.ai_tokens_7d)} tokens`}
            />
            <StatTile label="Photos uploaded (7d)" value={formatNumber(data.photos_uploaded_7d)} />
            <StatTile label="Storage used" value={formatBytes(data.storage_bytes_used)} />
            <StatTile
              label="API errors (24h)"
              value={formatNumber(data.api_errors_24h)}
              hint={data.api_errors_24h === 0 ? "All clear" : "Needs a look"}
              tone={data.api_errors_24h === 0 ? "success" : "danger"}
            />
            <StatTile
              label="Onboarded share"
              value={
                data.total_users
                  ? `${Math.round((data.active_users_30d / data.total_users) * 100)}%`
                  : "—"
              }
              hint="Active in the last 30 days"
            />
          </div>

          <div className="grid gap-4 xl:grid-cols-2">
            <Card>
              <CardHeader title="New registrations" description="Last 14 days" />
              <CardBody>
                <AreaTrend data={data.registrations_series} label="Registrations" />
              </CardBody>
            </Card>
            <Card>
              <CardHeader title="Workouts completed" description="Last 14 days" />
              <CardBody>
                <AreaTrend
                  data={data.workouts_series}
                  label="Workouts"
                  color="hsl(var(--success))"
                />
              </CardBody>
            </Card>
          </div>
        </>
      )}
    </>
  );
}
