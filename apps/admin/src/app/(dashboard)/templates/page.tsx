"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Star } from "lucide-react";

import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Table,
  TableSkeleton,
  Td,
  Th,
} from "@/components/ui";
import { api, type TemplateRow } from "@/lib/api";
import { titleCase } from "@/lib/utils";

export default function TemplatesPage() {
  const queryClient = useQueryClient();

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["admin", "templates"],
    queryFn: () => api.get<TemplateRow[]>("/api/v1/admin/templates"),
  });

  const feature = useMutation({
    mutationFn: ({ id, is_featured }: { id: string; is_featured: boolean }) =>
      api.post<TemplateRow>(`/api/v1/admin/templates/${id}/feature`, { is_featured }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["admin", "templates"] }),
  });

  return (
    <>
      <header>
        <h1 className="text-xl font-semibold">Workout templates</h1>
        <p className="text-sm text-muted">
          Starter plans users clone. Featured templates surface first in the app.
        </p>
      </header>

      <Card>
        {isError ? (
          <ErrorState title="We couldn't load the templates" onRetry={() => refetch()} />
        ) : isLoading || !data ? (
          <TableSkeleton columns={5} />
        ) : data.length === 0 ? (
          <EmptyState
            title="No templates yet"
            description="Run the seeder to load the starter plans."
          />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>Template</Th>
                <Th>Goal</Th>
                <Th>Structure</Th>
                <Th>Difficulty</Th>
                <Th>Featured</Th>
              </tr>
            </thead>
            <tbody>
              {data.map((template) => (
                <tr key={template.id} className="hover:bg-background">
                  <Td>
                    <p className="font-medium">{template.name}</p>
                    {template.description ? (
                      <p className="max-w-md text-sm text-muted">{template.description}</p>
                    ) : null}
                  </Td>
                  <Td className="text-muted">{template.goal ? titleCase(template.goal) : "—"}</Td>
                  <Td className="text-muted">
                    {template.days_per_week} days · {template.exercise_count} exercises
                    {template.estimated_minutes ? ` · ~${template.estimated_minutes} min` : ""}
                  </Td>
                  <Td>
                    <Badge>{template.difficulty ?? "—"}</Badge>
                  </Td>
                  <Td>
                    <Button
                      size="sm"
                      variant={template.is_featured ? "primary" : "secondary"}
                      loading={feature.isPending && feature.variables?.id === template.id}
                      onClick={() =>
                        feature.mutate({ id: template.id, is_featured: !template.is_featured })
                      }
                      aria-pressed={template.is_featured}
                    >
                      <Star
                        className="h-4 w-4"
                        aria-hidden
                        fill={template.is_featured ? "currentColor" : "none"}
                      />
                      {template.is_featured ? "Featured" : "Feature"}
                    </Button>
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
