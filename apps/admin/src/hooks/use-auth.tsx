"use client";

import { useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";

import { type AdminUserSummary, api, clearTokens, getAccessToken, logout } from "@/lib/api";

type AuthState = {
  user: AdminUserSummary | null;
  loading: boolean;
  signOut: () => Promise<void>;
  setUser: (user: AdminUserSummary | null) => void;
};

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AdminUserSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    // Restore the session from the stored token on first paint.
    if (!getAccessToken()) {
      setLoading(false);
      return;
    }
    api
      .get<AdminUserSummary>("/api/v1/profile")
      .then((profile) => {
        if (profile.role !== "admin") {
          clearTokens();
          setUser(null);
          return;
        }
        setUser(profile);
      })
      .catch(() => {
        clearTokens();
        setUser(null);
      })
      .finally(() => setLoading(false));
  }, []);

  const signOut = useCallback(async () => {
    await logout();
    setUser(null);
    router.replace("/login");
  }, [router]);

  const value = useMemo(() => ({ user, loading, signOut, setUser }), [user, loading, signOut]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const context = useContext(AuthContext);
  if (!context) throw new Error("useAuth must be used inside an AuthProvider");
  return context;
}
