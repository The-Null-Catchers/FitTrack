"use client";

import { useQuery } from "@tanstack/react-query";

import { Card, CardBody, CardHeader, ErrorState, Skeleton, StatTile } from "@/components/ui";
import { api, type StorageStats } from "@/lib/api";
import { formatBytes, formatNumber } from "@/lib/utils";

export default function StoragePage() {
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["admin", "storage"],
    queryFn: () => api.get<StorageStats>("/api/v1/admin/storage"),
  });

  if (isError) {
    return (
      <Card>
        <ErrorState title="We couldn't load storage usage" onRetry={() => refetch()} />
      </Card>
    );
  }

  return (
    <>
      <header>
        <h1 className="text-xl font-semibold">Storage</h1>
        <p className="text-sm text-muted">Object storage usage across the platform.</p>
      </header>

      {isLoading || !data ? (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {Array.from({ length: 4 }).map((_, index) => (
            <Card key={index} className="p-5">
              <Skeleton className="w-24" />
              <Skeleton className="mt-3 h-7 w-20" />
            </Card>
          ))}
        </div>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatTile label="Backend" value={data.backend} />
            <StatTile label="Total stored" value={formatBytes(data.total_bytes)} />
            <StatTile
              label="Progress photos"
              value={formatNumber(data.progress_photos)}
              hint={formatBytes(data.progress_photo_bytes)}
            />
            <StatTile label="Avatars" value={formatNumber(data.avatars)} />
          </div>

          <Card>
            <CardHeader title="Privacy" />
            <CardBody className="space-y-2 text-sm text-muted">
              <p>
                Progress photos are private to the user who uploaded them. This page reports counts
                and byte totals only — there is no administrative path to view a photo.
              </p>
              <p>
                Photos are served exclusively through short-lived signed URLs; raw storage keys are
                never returned by the API.
              </p>
              <p>
                When an account is deleted, a background job removes every stored object belonging
                to it 30 days later.
              </p>
            </CardBody>
          </Card>
        </>
      )}
    </>
  );
}
