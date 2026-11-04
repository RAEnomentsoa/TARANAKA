/** Runtime settings, read once from the Vite environment. */
export const config = {
  idleTimeoutMinutes: Number(import.meta.env.VITE_IDLE_TIMEOUT_MINUTES ?? 15) || 15,
}
