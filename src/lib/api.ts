import { invoke } from "@tauri-apps/api/core";
import type { DownloadRecord, VideoInfo } from "@/types/download";

export const api = {
  fetchVideoInfo: (url: string) => invoke<VideoInfo>("fetch_video_info", { url }),
  startDownload: (
    url: string,
    title: string,
    formatSelector: string,
    outputDir: string,
    outputFormat: string,
  ) => invoke<number>("start_download", { url, title, formatSelector, outputDir, outputFormat }),
  cancelDownload: (downloadId: number) => invoke<void>("cancel_download", { downloadId }),
  pauseDownload: (downloadId: number) => invoke<void>("pause_download", { downloadId }),
  resumeDownload: (downloadId: number) => invoke<void>("resume_download", { downloadId }),
  listDownloads: () => invoke<DownloadRecord[]>("list_downloads"),
  deleteDownloadRecord: (downloadId: number, deleteFile: boolean) =>
    invoke<void>("delete_download_record", { downloadId, deleteFile }),
  /** Resolves to the new version string if an update was applied, or `null` if already up to date. */
  updateYtdlp: () => invoke<string | null>("update_ytdlp"),
};
