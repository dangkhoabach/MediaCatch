import { downloadDir } from "@tauri-apps/api/path";

const KEYS = {
  outputDir: "dkb-downloader:outputDir",
  outputFormat: "dkb-downloader:outputFormat",
};

export type OutputFormat = "mp4" | "mkv";

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
