import { apiFetch } from './client';

export interface HealthStatus {
  status: string;
}

/** GET /api/v1/health through the shared API client. */
export function getHealth(): Promise<HealthStatus> {
  return apiFetch<HealthStatus>('/health');
}
