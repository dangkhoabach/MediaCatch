import { invoke } from "@tauri-apps/api/core";
import type { DownloadRecord, PlaylistEntry, VideoInfo, WatchedChannel } from "@/types/download";
import { getCookiesBrowser, getUseAria2c } from "@/lib/settings";

/** `"none"` means "don't read any browser's cookies" — omit the arg entirely rather than send the literal string. */
function cookiesBrowserArg(): string | null {
  const browser = getCookiesBrowser();
  return browser === "none" ? null : browser;
}

export const api = {
  fetchVideoInfo: (url: string) =>
    invoke<VideoInfo>("fetch_video_info", { url, cookiesBrowser: cookiesBrowserArg() }),
  startDownload: (
    url: string,
    title: string,
    formatSelector: string,
    outputDir: string,
    outputFormat: string,
    embedMetadata: boolean,
  ) =>
    invoke<number>("start_download", {
      url,
      title,
      formatSelector,
      outputDir,
      outputFormat,
      embedMetadata,
      cookiesBrowser: cookiesBrowserArg(),
      useAria2c: getUseAria2c(),
    }),
  cancelDownload: (downloadId: number) => invoke<void>("cancel_download", { downloadId }),
  pauseDownload: (downloadId: number) => invoke<void>("pause_download", { downloadId }),
  resumeDownload: (downloadId: number) => invoke<void>("resume_download", { downloadId }),
  listDownloads: () => invoke<DownloadRecord[]>("list_downloads"),
  deleteDownloadRecord: (downloadId: number, deleteFile: boolean) =>
    invoke<void>("delete_download_record", { downloadId, deleteFile }),
  /** Resolves to the new version string if an update was applied, or `null` if already up to date. */
  updateYtdlp: () => invoke<string | null>("update_ytdlp"),
  expandPlaylist: (url: string) => invoke<PlaylistEntry[]>("expand_playlist", { url }),
  addWatchedChannel: (url: string, outputDir: string, outputFormat: string) =>
    invoke<WatchedChannel>("add_watched_channel", { url, outputDir, outputFormat }),
  listWatchedChannels: () => invoke<WatchedChannel[]>("list_watched_channels"),
  removeWatchedChannel: (id: number) => invoke<void>("remove_watched_channel", { id }),
  setWatchedChannelEnabled: (id: number, enabled: boolean) =>
    invoke<void>("set_watched_channel_enabled", { id, enabled }),
};
