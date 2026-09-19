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
  Select,
  Table,
  TableSkeleton,
  Td,
  Th,
} from "@/components/ui";
import { api, type ExerciseRow, type Page } from "@/lib/api";
import { titleCase } from "@/lib/utils";

const MUSCLE_GROUPS = [
  "chest",
  "back",
  "shoulders",
  "arms",
  "legs",
  "core",
  "cardio",
  "mobility",
  "full_body",
];

const DIFFICULTY_TONE = {
  beginner: "success",
  intermediate: "info",
  advanced: "warning",
} as const;

export default function ExercisesPage() {
  const [query, setQuery] = useState("");
  const [muscleGroup, setMuscleGroup] = useState("");
  const [page, setPage] = useState(1);

  const params = new URLSearchParams({ page: String(page), per_page: "20", sort: "name" });
  if (query) params.set("q", query);
  if (muscleGroup) params.set("muscle_group", muscleGroup);

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ["admin", "exercises", page, query, muscleGroup],
    queryFn: () => api.get<Page<ExerciseRow>>(`/api/v1/exercises?${params}`),
    placeholderData: keepPreviousData,
  });

  return (
    <>
      <header>
        <h1 className="text-xl font-semibold">Exercise library</h1>
        <p className="text-sm text-muted">
          The shared catalogue every user&apos;s programs are built from.
        </p>
      </header>

      <Card>
        <div className="flex flex-wrap items-center gap-3 border-b p-4">
          <Input
            type="search"
            className="max-w-xs"
            placeholder="Search exercises"
            aria-label="Search exercises"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setPage(1);
            }}
          />
          <Select
            aria-label="Filter by muscle group"
            value={muscleGroup}
            onChange={(event) => {
              setMuscleGroup(event.target.value);
              setPage(1);
            }}
          >
            <option value="">All muscle groups</option>
            {MUSCLE_GROUPS.map((group) => (
              <option key={group} value={group}>
                {titleCase(group)}
              </option>
            ))}
          </Select>
        </div>

        {isError ? (
          <ErrorState title="We couldn't load the exercise library" onRetry={() => refetch()} />
        ) : isLoading || !data ? (
          <TableSkeleton columns={5} />
        ) : data.items.length === 0 ? (
          <EmptyState
            title="No exercises match that search"
            description="Try a different name or muscle group."
          />
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>Name</Th>
                  <Th>Muscle group</Th>
                  <Th>Equipment</Th>
                  <Th>Difficulty</Th>
                  <Th>Tracking</Th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((exercise) => (
                  <tr key={exercise.id} className="hover:bg-background">
                    <Td>
                      <p className="font-medium">{exercise.name}</p>
                      {exercise.name_ar ? (
                        <p className="text-sm text-muted" dir="rtl" lang="ar">
                          {exercise.name_ar}
                        </p>
                      ) : null}
                    </Td>
                    <Td>{titleCase(exercise.muscle_group)}</Td>
                    <Td className="text-muted">{titleCase(exercise.equipment)}</Td>
                    <Td>
                      <Badge
                        tone={
                          DIFFICULTY_TONE[exercise.difficulty as keyof typeof DIFFICULTY_TONE] ??
                          "neutral"
                        }
                      >
                        {exercise.difficulty}
                      </Badge>
                    </Td>
                    <Td className="text-muted">{titleCase(exercise.default_tracking_type)}</Td>
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
