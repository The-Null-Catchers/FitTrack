/**
 * Typed API client.
 *
 * Access tokens are short-lived, so every request goes through `request`,
 * which transparently refreshes once on a 401 and replays the call. Tokens
 * live in memory plus sessionStorage: the dashboard is an operator tool, and
 * keeping them out of localStorage limits the blast radius of an XSS bug.
 */

export const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

const ACCESS_KEY = "fittrack.admin.access";
const REFRESH_KEY = "fittrack.admin.refresh";

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: string,
    readonly details: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = "ApiError";
  }
}

type Tokens = { access_token: string; refresh_token: string };

function store(): Storage | null {
  return typeof window === "undefined" ? null : window.sessionStorage;
}

export function getAccessToken(): string | null {
  return store()?.getItem(ACCESS_KEY) ?? null;
}

export function setTokens(tokens: Tokens): void {
  store()?.setItem(ACCESS_KEY, tokens.access_token);
  store()?.setItem(REFRESH_KEY, tokens.refresh_token);
}

export function clearTokens(): void {
  store()?.removeItem(ACCESS_KEY);
  store()?.removeItem(REFRESH_KEY);
}

async function parseError(response: Response): Promise<ApiError> {
  let message = "Something went wrong. Please try again.";
  let code = "error";
  let details: Record<string, unknown> = {};
  try {
    const body = await response.json();
    if (body?.error) {
      message = body.error.message ?? message;
      code = body.error.code ?? code;
      details = body.error.details ?? {};
    }
  } catch {
    // A non-JSON body (a gateway error page, say) keeps the default message.
  }
  return new ApiError(message, response.status, code, details);
}

async function refreshTokens(): Promise<boolean> {
  const refreshToken = store()?.getItem(REFRESH_KEY);
  if (!refreshToken) return false;

  const response = await fetch(`${API_URL}/api/v1/auth/refresh`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (!response.ok) {
    clearTokens();
    return false;
  }
  setTokens(await response.json());
  return true;
}

export async function request<T>(
  path: string,
  init: RequestInit & { retryOnUnauthorized?: boolean } = {},
): Promise<T> {
  const { retryOnUnauthorized = true, ...options } = init;
  const token = getAccessToken();

  const response = await fetch(`${API_URL}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });

  if (response.status === 401 && retryOnUnauthorized && (await refreshTokens())) {
    return request<T>(path, { ...init, retryOnUnauthorized: false });
  }

  if (!response.ok) throw await parseError(response);
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: "POST", body: body ? JSON.stringify(body) : undefined }),
  patch: <T>(path: string, body: unknown) =>
    request<T>(path, { method: "PATCH", body: JSON.stringify(body) }),
  delete: <T>(path: string) => request<T>(path, { method: "DELETE" }),
};

export async function login(email: string, password: string): Promise<AdminUserSummary> {
  const response = await fetch(`${API_URL}/api/v1/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email,
      password,
      device: { device_name: "Admin dashboard", platform: "web" },
    }),
  });
  if (!response.ok) throw await parseError(response);

  const body = (await response.json()) as Tokens & { user: AdminUserSummary };
  if (body.user.role !== "admin") {
    throw new ApiError("This dashboard is restricted to administrators.", 403, "forbidden");
  }
  setTokens(body);
  return body.user;
}

export async function logout(): Promise<void> {
  try {
    await api.post("/api/v1/auth/logout", { all_devices: false });
  } catch {
    // Signing out locally must succeed even if the API call doesn't.
  }
  clearTokens();
}

// --- response types --------------------------------------------------------

export type AdminUserSummary = {
  id: string;
  email: string;
  full_name: string;
  role: "user" | "admin" | "support";
};

export type Page<T> = {
  items: T[];
  meta: {
    page: number;
    per_page: number;
    total: number;
    total_pages: number;
    has_next: boolean;
    has_previous: boolean;
  };
};

export type MetricPoint = { day: string; value: number };

export type Overview = {
  total_users: number;
  active_users_7d: number;
  active_users_30d: number;
  new_registrations_7d: number;
  workouts_completed_7d: number;
  workouts_completed_total: number;
  ai_requests_7d: number;
  ai_tokens_7d: number;
  photos_uploaded_7d: number;
  storage_bytes_used: number;
  api_errors_24h: number;
  registrations_series: MetricPoint[];
  workouts_series: MetricPoint[];
};

export type UserRow = {
  id: string;
  email: string;
  full_name: string;
  role: string;
  status: "active" | "suspended" | "pending_deletion";
  email_verified: boolean;
  onboarding_completed: boolean;
  subscription_tier: string;
  workout_count: number;
  last_login_at: string | null;
  created_at: string;
};

export type UserDetail = UserRow & {
  locale: string;
  timezone: string;
  progress_photo_count: number;
  ai_message_count: number;
  session_count: number;
};

export type ExerciseRow = {
  id: string;
  slug: string;
  name: string;
  name_ar: string | null;
  muscle_group: string;
  equipment: string;
  difficulty: string;
  exercise_type: string;
  default_tracking_type: string;
  image_url: string | null;
  is_public: boolean;
};

export type TemplateRow = {
  id: string;
  name: string;
  description: string | null;
  goal: string | null;
  difficulty: string | null;
  location: string | null;
  days_per_week: number;
  estimated_minutes: number | null;
  day_count: number;
  exercise_count: number;
  is_featured: boolean;
};

export type AIUsageRow = {
  day: string;
  kind: string;
  requests: number;
  input_tokens: number;
  output_tokens: number;
  failures: number;
};

export type StorageStats = {
  backend: string;
  progress_photos: number;
  progress_photo_bytes: number;
  exercise_media: number;
  avatars: number;
  total_bytes: number;
};

export type SystemHealth = {
  api: string;
  database: string;
  redis: string;
  storage: string;
  worker: string;
  version: string;
  environment: string;
  uptime_seconds: number;
  checked_at: string;
};

export type AuditLogRow = {
  id: string;
  actor_id: string | null;
  actor_email: string | null;
  action: string;
  entity_type: string | null;
  entity_id: string | null;
  ip_address: string | null;
  metadata_json: Record<string, unknown>;
  note: string | null;
  created_at: string;
};
