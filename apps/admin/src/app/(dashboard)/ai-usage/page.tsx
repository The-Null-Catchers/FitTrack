"use client";

import { useQuery } from "@tanstack/react-query";

import {
  Badge,
  Card,
  EmptyState,
  ErrorState,
  StatTile,
  Table,
  TableSkeleton,
  Td,
  Th,
} from "@/components/ui";
import { api, type AIUsageRow } from "@/lib/api";
import { formatNumber, titleCase } from "@/lib/utils";

export default function AIUsagePage() {
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["admin", "ai-usage"],
    queryFn: () => api.get<AIUsageRow[]>("/api/v1/admin/ai-usage?days=14"),
  });

  const totals = (data ?? []).reduce(
    (accumulator, row) => ({
      requests: accumulator.requests + row.requests,
      tokens: accumulator.tokens + row.input_tokens + row.output_tokens,
      failures: accumulator.failures + row.failures,
    }),
    { requests: 0, tokens: 0, failures: 0 },
  );

  return (
    <>
      <header>
        <h1 className="text-xl font-semibold">AI usage</h1>
        <p className="text-sm text-muted">FitCoach requests and token spend, last 14 days.</p>
      </header>

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Requests" value={formatNumber(totals.requests)} />
        <StatTile label="Tokens" value={formatNumber(totals.tokens)} />
        <StatTile
          label="Failures"
          value={formatNumber(totals.failures)}
          hint={totals.failures === 0 ? "All succeeded" : "Investigate"}
          tone={totals.failures === 0 ? "success" : "danger"}
        />
      </div>

      <Card>
        {isError ? (
          <ErrorState title="We couldn't load AI usage" onRetry={() => refetch()} />
        ) : isLoading || !data ? (
          <TableSkeleton columns={5} />
        ) : data.length === 0 ? (
          <EmptyState
            title="No AI activity yet"
            description="FitCoach requests will appear here once users start chatting or generating plans."
          />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>Day</Th>
                <Th>Kind</Th>
                <Th>Requests</Th>
                <Th>Input tokens</Th>
                <Th>Output tokens</Th>
                <Th>Failures</Th>
              </tr>
            </thead>
            <tbody>
              {data.map((row) => (
                <tr key={`${row.day}-${row.kind}`} className="hover:bg-background">
                  <Td>{row.day}</Td>
                  <Td>
                    <Badge tone="primary">{titleCase(row.kind)}</Badge>
                  </Td>
                  <Td className="tabular-nums">{formatNumber(row.requests)}</Td>
                  <Td className="tabular-nums text-muted">{formatNumber(row.input_tokens)}</Td>
                  <Td className="tabular-nums text-muted">{formatNumber(row.output_tokens)}</Td>
                  <Td className="tabular-nums">
                    {row.failures > 0 ? (
                      <Badge tone="danger">{row.failures}</Badge>
                    ) : (
                      <span className="text-muted">0</span>
                    )}
                  </Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </>
  );
}
