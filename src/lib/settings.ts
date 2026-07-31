import { downloadDir } from "@tauri-apps/api/path";

const KEYS = {
  outputDir: "dkb-downloader:outputDir",
  outputFormat: "dkb-downloader:outputFormat",
  notificationsEnabled: "dkb-downloader:notificationsEnabled",
  embedMetadata: "dkb-downloader:embedMetadata",
  cookiesBrowser: "dkb-downloader:cookiesBrowser",
  useAria2c: "dkb-downloader:useAria2c",
};

export type OutputFormat = "mp4" | "mkv";

export type CookiesBrowser = "none" | "safari" | "chrome" | "firefox" | "edge" | "brave";

export function getOutputDir(): string {
  return localStorage.getItem(KEYS.outputDir) ?? "";
}

export function setOutputDir(dir: string) {
  localStorage.setItem(KEYS.outputDir, dir);
}

/** Falls back to the OS Downloads folder and persists it the first time the app runs. */
export async function ensureOutputDir(): Promise<string> {
  const current = getOutputDir();
  if (current) return current;
  const fallback = await downloadDir();
  setOutputDir(fallback);
  return fallback;
}

export function getOutputFormat(): OutputFormat {
  return (localStorage.getItem(KEYS.outputFormat) as OutputFormat) ?? "mp4";
}

export function setOutputFormat(format: OutputFormat) {
  localStorage.setItem(KEYS.outputFormat, format);
}

export function getNotificationsEnabled(): boolean {
  return localStorage.getItem(KEYS.notificationsEnabled) !== "false";
}

export function setNotificationsEnabled(enabled: boolean) {
  localStorage.setItem(KEYS.notificationsEnabled, String(enabled));
}

/** Off by default — embedding subs/chapters/thumbnail adds post-processing time to every download. */
export function getEmbedMetadata(): boolean {
  return localStorage.getItem(KEYS.embedMetadata) === "true";
}

export function setEmbedMetadata(enabled: boolean) {
  localStorage.setItem(KEYS.embedMetadata, String(enabled));
}

/** "none" by default — reading another app's browser cookies is a deliberate opt-in. */
export function getCookiesBrowser(): CookiesBrowser {
  return (localStorage.getItem(KEYS.cookiesBrowser) as CookiesBrowser) ?? "none";
}

export function setCookiesBrowser(browser: CookiesBrowser) {
  localStorage.setItem(KEYS.cookiesBrowser, browser);
}

/** Off by default — requires the user to have aria2c installed separately (e.g. `brew install aria2`). */
export function getUseAria2c(): boolean {
  return localStorage.getItem(KEYS.useAria2c) === "true";
}

export function setUseAria2c(enabled: boolean) {
  localStorage.setItem(KEYS.useAria2c, String(enabled));
}
