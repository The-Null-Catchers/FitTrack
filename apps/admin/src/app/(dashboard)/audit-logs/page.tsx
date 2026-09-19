"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { useState } from "react";

import {
  Badge,
  Card,
  EmptyState,
  ErrorState,
  Input,
  Pagination,
  Table,
  TableSkeleton,
  Td,
  Th,
} from "@/components/ui";
import { api, type AuditLogRow, type Page } from "@/lib/api";
import { formatDateTime } from "@/lib/utils";

function actionTone(action: string) {
  if (action.startsWith("admin.")) return "primary" as const;
  if (action.includes("failed") || action.includes("reuse")) return "danger" as const;
  if (action.startsWith("account.")) return "warning" as const;
  return "neutral" as const;
}

export default function AuditLogsPage() {
  const [action, setAction] = useState("");
  const [page, setPage] = useState(1);

  const params = new URLSearchParams({ page: String(page), per_page: "25" });
  if (action) params.set("action", action);

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["admin", "audit-logs", page, action],
    queryFn: () => api.get<Page<AuditLogRow>>(`/api/v1/admin/audit-logs?${params}`),
    placeholderData: keepPreviousData,
  });

  return (
    <>
      <header>
        <h1 className="text-xl font-semibold">Audit log</h1>
        <p className="text-sm text-muted">
          Every authentication event and administrative change, append-only.
        </p>
      </header>

      <Card>
        <div className="border-b p-4">
          <Input
            type="search"
            className="max-w-xs"
            placeholder="Filter by action, e.g. auth.login"
            aria-label="Filter by action"
            value={action}
            onChange={(event) => {
              setAction(event.target.value);
              setPage(1);
            }}
          />
        </div>

        {isError ? (
          <ErrorState title="We couldn't load the audit log" onRetry={() => refetch()} />
        ) : isLoading || !data ? (
          <TableSkeleton columns={4} rows={8} />
        ) : data.items.length === 0 ? (
          <EmptyState
            title="No entries match that filter"
            description="Try a broader action name, or clear the filter."
          />
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>When</Th>
                  <Th>Action</Th>
                  <Th>Actor</Th>
                  <Th>Target</Th>
                  <Th>Details</Th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((entry) => (
                  <tr key={entry.id} className="hover:bg-background">
                    <Td className="whitespace-nowrap text-muted">
                      {formatDateTime(entry.created_at)}
                    </Td>
                    <Td>
                      <Badge tone={actionTone(entry.action)}>{entry.action}</Badge>
                    </Td>
                    <Td className="text-muted">{entry.actor_email ?? "—"}</Td>
                    <Td className="font-mono text-xs text-muted">
                      {entry.entity_type ? `${entry.entity_type}` : "—"}
                    </Td>
                    <Td className="max-w-xs">
                      {entry.note ? <p className="text-sm">{entry.note}</p> : null}
                      {Object.keys(entry.metadata_json).length > 0 ? (
                        <p className="truncate font-mono text-xs text-muted">
                          {JSON.stringify(entry.metadata_json)}
                        </p>
                      ) : null}
                    </Td>
                  </tr>
                ))}
              </tbody>
            </Table>
            <Pagination
              page={data.meta.page}
              totalPages={data.meta.total_pages}
              total={data.meta.total}
              onChange={setPage}
            />
          </>
        )}
      </Card>
    </>
  );
}
