"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, ShieldAlert } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";

import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  ErrorState,
  Field,
  Input,
  Skeleton,
  StatTile,
} from "@/components/ui";
import { ApiError, api, type UserDetail } from "@/lib/api";
import { formatDateTime, relativeTime } from "@/lib/utils";

export default function UserDetailPage() {
  const { id } = useParams<{ id: string }>();
  const queryClient = useQueryClient();
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["admin", "user", id],
    queryFn: () => api.get<UserDetail>(`/api/v1/admin/users/${id}`),
  });

  const mutation = useMutation({
    mutationFn: (body: { status?: string; role?: string; note?: string }) =>
      api.patch<UserDetail>(`/api/v1/admin/users/${id}`, body),
    onSuccess: (updated) => {
      queryClient.setQueryData(["admin", "user", id], updated);
      queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
      queryClient.invalidateQueries({ queryKey: ["admin", "audit-logs"] });
      setNote("");
      setError(null);
    },
    onError: (caught) =>
      setError(caught instanceof ApiError ? caught.message : "That change didn't go through."),
  });

  if (isError) {
    return (
      <Card>
        <ErrorState title="We couldn't load this user" onRetry={() => refetch()} />
      </Card>
    );
  }

  return (
    <>
      <Link
        href="/users"
        className="inline-flex items-center gap-1.5 text-sm text-muted hover:text-foreground"
      >
        <ArrowLeft className="h-4 w-4" aria-hidden />
        Back to users
      </Link>

      {isLoading || !data ? (
        <Card className="p-5">
          <Skeleton className="w-48" />
          <Skeleton className="mt-3 h-7 w-64" />
        </Card>
      ) : (
        <>
          <header className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <h1 className="text-xl font-semibold">{data.full_name}</h1>
              <p className="text-sm text-muted">{data.email}</p>
              <div className="mt-2 flex flex-wrap gap-1.5">
                <Badge tone={data.status === "active" ? "success" : "danger"}>
                  {data.status.replace("_", " ")}
                </Badge>
                <Badge tone={data.role === "admin" ? "primary" : "neutral"}>{data.role}</Badge>
                <Badge tone={data.email_verified ? "success" : "warning"}>
                  {data.email_verified ? "verified" : "unverified"}
                </Badge>
                <Badge>{data.subscription_tier}</Badge>
              </div>
            </div>
          </header>

          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatTile label="Workouts completed" value={String(data.workout_count)} />
            <StatTile label="Active sessions" value={String(data.session_count)} />
            <StatTile
              label="Progress photos"
              value={String(data.progress_photo_count)}
              hint="Private — not viewable here"
            />
            <StatTile label="Last seen" value={relativeTime(data.last_login_at)} />
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card>
              <CardHeader title="Account" />
              <CardBody className="space-y-2 text-sm">
                <Row label="User ID" value={data.id} mono />
                <Row label="Locale" value={data.locale} />
                <Row label="Timezone" value={data.timezone} />
                <Row
                  label="Onboarding"
                  value={data.onboarding_completed ? "Complete" : "Pending"}
                />
                <Row label="Joined" value={formatDateTime(data.created_at)} />
                <Row label="Last login" value={formatDateTime(data.last_login_at)} />
              </CardBody>
            </Card>

            <Card>
              <CardHeader
                title="Moderation"
                description="Suspending an account signs it out of every device immediately."
              />
              <CardBody className="space-y-4">
                <Field label="Reason" hint="Recorded in the audit log.">
                  <Input
                    value={note}
                    onChange={(event) => setNote(event.target.value)}
                    placeholder="e.g. Repeated content reports"
                  />
                </Field>

                {error ? (
                  <p role="alert" className="rounded-sm bg-danger/10 px-3 py-2 text-sm text-danger">
                    {error}
                  </p>
                ) : null}

                <div className="flex flex-wrap gap-2">
                  {data.status === "active" ? (
                    <Button
                      variant="danger"
                      loading={mutation.isPending}
                      onClick={() => mutation.mutate({ status: "suspended", note })}
                    >
                      <ShieldAlert className="h-4 w-4" aria-hidden />
                      Suspend account
                    </Button>
                  ) : (
                    <Button
                      loading={mutation.isPending}
                      onClick={() => mutation.mutate({ status: "active", note })}
                    >
                      Reinstate account
                    </Button>
                  )}
                </div>

                <p className="rounded-sm bg-background px-3 py-2 text-sm text-muted">
                  Progress photos, nutrition logs and FitCoach conversations are private to the user
                  and are never exposed in this dashboard.
                </p>
              </CardBody>
            </Card>
          </div>
        </>
      )}
    </>
  );
}

function Row({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex items-center justify-between gap-4 border-b py-1.5 last:border-b-0">
      <span className="text-muted">{label}</span>
      <span className={mono ? "font-mono text-xs" : undefined}>{value}</span>
    </div>
  );
}
