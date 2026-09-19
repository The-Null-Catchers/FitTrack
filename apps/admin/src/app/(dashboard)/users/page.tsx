"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useState } from "react";

import {
  Badge,
  Card,
  EmptyState,
  ErrorState,
  Input,
  Pagination,
  Select,
  Table,
  TableSkeleton,
  Td,
  Th,
} from "@/components/ui";
import { api, type Page, type UserRow } from "@/lib/api";
import { formatDate, relativeTime } from "@/lib/utils";

const STATUS_TONE = {
  active: "success",
  suspended: "danger",
  pending_deletion: "warning",
} as const;

export default function UsersPage() {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(1);

  const params = new URLSearchParams({ page: String(page), per_page: "20" });
  if (query) params.set("q", query);
  if (status) params.set("status", status);

  const { data, isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ["admin", "users", page, query, status],
    queryFn: () => api.get<Page<UserRow>>(`/api/v1/admin/users?${params}`),
    placeholderData: keepPreviousData,
  });

  return (
    <>
      <header>
        <h1 className="text-xl font-semibold">Users</h1>
        <p className="text-sm text-muted">Search accounts and manage access.</p>
      </header>

      <Card>
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <Input
            type="search"
            className="max-w-xs"
            placeholder="Search name or email"
            aria-label="Search users"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setPage(1);
            }}
          />
          <Select
            aria-label="Filter by status"
            value={status}
            onChange={(event) => {
              setStatus(event.target.value);
              setPage(1);
            }}
          >
            <option value="">All statuses</option>
            <option value="active">Active</option>
            <option value="suspended">Suspended</option>
            <option value="pending_deletion">Pending deletion</option>
          </Select>
          {isFetching ? <span className="text-sm text-muted">Updating…</span> : null}
        </div>

        {isError ? (
          <ErrorState title="We couldn't load the user list" onRetry={() => refetch()} />
        ) : isLoading || !data ? (
          <TableSkeleton columns={5} />
        ) : data.items.length === 0 ? (
          <EmptyState
            title="No users match that search"
            description="Try a different name, email or status filter."
          />
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>User</Th>
                  <Th>Status</Th>
                  <Th>Workouts</Th>
                  <Th>Last seen</Th>
                  <Th>Joined</Th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((user) => (
                  <tr key={user.id} className="hover:bg-background">
                    <Td>
                      <Link
                        href={`/users/${user.id}`}
                        className="font-medium text-primary hover:underline"
                      >
                        {user.full_name}
                      </Link>
                      <p className="text-sm text-muted">{user.email}</p>
                    </Td>
                    <Td>
                      <div className="flex flex-wrap gap-1.5">
                        <Badge tone={STATUS_TONE[user.status]}>
                          {user.status.replace("_", " ")}
                        </Badge>
                        {user.role === "admin" ? <Badge tone="primary">admin</Badge> : null}
                        {!user.email_verified ? <Badge tone="warning">unverified</Badge> : null}
                      </div>
                    </Td>
                    <Td className="tabular-nums">{user.workout_count}</Td>
                    <Td className="text-muted">{relativeTime(user.last_login_at)}</Td>
                    <Td className="text-muted">{formatDate(user.created_at)}</Td>
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
