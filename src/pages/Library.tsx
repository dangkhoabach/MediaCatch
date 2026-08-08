import { useEffect, useState } from "react";
import { useNavigate } from "react-router";
import { listen } from "@tauri-apps/api/event";
import { openPath, revealItemInDir } from "@tauri-apps/plugin-opener";
import { FolderOpen, Play, RefreshCw, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { api } from "@/lib/api";
import { useTranslation } from "@/lib/i18n/context";
import { useHomeState } from "@/lib/home-state";
import type { DownloadRecord, UrlHistoryEntry } from "@/types/download";
import type { TranslationKey } from "@/lib/i18n/translations";

const statusKey: Record<DownloadRecord["status"], TranslationKey> = {
  downloading: "library.status.downloading",
  completed: "library.status.completed",
  error: "library.status.error",
  canceled: "library.status.canceled",
};

const statusVariant: Record<DownloadRecord["status"], "default" | "destructive" | "secondary"> = {
  downloading: "secondary",
  completed: "default",
  error: "destructive",
  canceled: "secondary",
};

type Tab = "downloads" | "recent";

export function LibraryPage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { setPendingFetchUrl } = useHomeState();
  const [tab, setTab] = useState<Tab>("downloads");
  const [records, setRecords] = useState<DownloadRecord[]>([]);
  const [recentLinks, setRecentLinks] = useState<UrlHistoryEntry[]>([]);
  const [recentSearch, setRecentSearch] = useState("");

  async function refresh() {
    try {
      const all = await api.listDownloads();
      setRecords(all.filter((d) => d.status !== "downloading"));
    } catch {
      // keep previous list on transient failure
    }
  }

  function refreshRecent() {
    api.listUrlHistory().then(setRecentLinks).catch(() => {});
  }

  useEffect(() => {
    refresh();
    const unlistenComplete = listen("download-complete", refresh);
    const unlistenError = listen("download-error", refresh);
    return () => {
      unlistenComplete.then((fn) => fn());
      unlistenError.then((fn) => fn());
    };
  }, []);

  useEffect(() => {
    if (tab === "recent") refreshRecent();
  }, [tab]);

  async function handleDelete(id: number, deleteFile: boolean) {
    try {
      await api.deleteDownloadRecord(id, deleteFile);
      refresh();
    } catch (e) {
      toast.error(t("library.deleteError"), { description: String(e) });
    }
  }

  async function handleOpen(path: string) {
    try {
      await openPath(path);
    } catch (e) {
      toast.error(t("library.openError"), { description: String(e) });
    }
  }

  async function handleReveal(path: string) {
    try {
      await revealItemInDir(path);
    } catch (e) {
      toast.error(t("library.revealError"), { description: String(e) });
    }
  }

  function handleRefetch(url: string) {
    setPendingFetchUrl(url);
    navigate("/");
  }

  async function handleDeleteRecent(id: number) {
    await api.deleteUrlHistoryEntry(id).catch(() => {});
    refreshRecent();
  }

  async function handleClearRecent() {
    await api.clearUrlHistory().catch(() => {});
    refreshRecent();
  }

  const filteredRecent = recentSearch.trim()
    ? recentLinks.filter((e) => (e.title + e.url).toLowerCase().includes(recentSearch.trim().toLowerCase()))
    : recentLinks;

  return (
    <div className="flex h-full flex-col gap-3 overflow-y-auto p-6 pt-14">
      <div className="flex gap-1 self-start rounded-lg border border-border p-1">
        <button
          type="button"
          onClick={() => setTab("downloads")}
          className={`rounded-md px-3 py-1 text-sm ${
            tab === "downloads" ? "bg-accent text-accent-foreground" : "text-muted-foreground"
          }`}
        >
          {t("library.tabDownloads")}
        </button>
        <button
          type="button"
          onClick={() => setTab("recent")}
          className={`rounded-md px-3 py-1 text-sm ${
            tab === "recent" ? "bg-accent text-accent-foreground" : "text-muted-foreground"
          }`}
        >
          {t("library.tabRecent")}
        </button>
      </div>

      {tab === "downloads" ? (
        records.length === 0 ? (
          <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
            {t("library.empty")}
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {records.map((r) => (
              <div key={r.id} className="flex items-center gap-3 rounded-lg border border-border p-3">
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{r.title}</p>
                  <p className="text-xs text-muted-foreground">
                    {new Date(r.created_at + "Z").toLocaleString()}
                  </p>
                  {r.status === "error" && r.error_message && (
                    <p className="truncate text-xs text-destructive">{r.error_message}</p>
                  )}
                </div>
                <Badge variant={statusVariant[r.status]}>{t(statusKey[r.status])}</Badge>
                {r.status === "completed" && r.output_path && (
                  <>
                    <Button size="icon" variant="ghost" onClick={() => handleOpen(r.output_path!)}>
                      <Play className="size-4" />
                    </Button>
                    <Button size="icon" variant="ghost" onClick={() => handleReveal(r.output_path!)}>
                      <FolderOpen className="size-4" />
                    </Button>
                  </>
                )}
                <Button size="icon" variant="ghost" onClick={() => handleDelete(r.id, false)}>
                  <Trash2 className="size-4" />
                </Button>
              </div>
            ))}
          </div>
        )
      ) : (
        <div className="flex flex-col gap-2">
          <div className="flex items-center gap-2">
            <Input
              placeholder={t("library.recentSearchPlaceholder")}
              value={recentSearch}
              onChange={(e) => setRecentSearch(e.target.value)}
            />
            {recentLinks.length > 0 && (
              <Button variant="ghost" size="sm" onClick={handleClearRecent}>
                {t("library.recentClear")}
              </Button>
            )}
          </div>

          {filteredRecent.length === 0 ? (
            <div className="flex flex-1 items-center justify-center pt-8 text-sm text-muted-foreground">
              {t("library.recentEmpty")}
            </div>
          ) : (
            filteredRecent.map((entry) => (
              <div key={entry.id} className="flex items-center gap-3 rounded-lg border border-border p-3">
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{entry.title}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {new Date(entry.last_fetched_at + "Z").toLocaleString()}
                    {entry.fetch_count > 1 && ` · ${t("library.recentFetchCount", { count: entry.fetch_count })}`}
                  </p>
                </div>
                <Button size="icon" variant="ghost" onClick={() => handleRefetch(entry.url)}>
                  <RefreshCw className="size-4" />
                </Button>
                <Button size="icon" variant="ghost" onClick={() => handleDeleteRecent(entry.id)}>
                  <Trash2 className="size-4" />
                </Button>
              </div>
            ))
          )}
        </div>
      )}
    </div>
  );
}
