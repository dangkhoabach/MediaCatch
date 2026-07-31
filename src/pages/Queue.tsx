import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { Pause, Play, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { api } from "@/lib/api";
import { useTranslation } from "@/lib/i18n/context";
import type { DownloadProgress, DownloadRecord } from "@/types/download";

export function QueuePage() {
  const { t } = useTranslation();
  const [downloads, setDownloads] = useState<DownloadRecord[]>([]);
  const [progressById, setProgressById] = useState<Record<number, DownloadProgress>>({});
  const [pausedIds, setPausedIds] = useState<Set<number>>(new Set());

  async function refresh() {
    try {
      const all = await api.listDownloads();
      setDownloads(all.filter((d) => d.status === "downloading"));
    } catch {
      // keep previous list on transient failure
    }
  }

  useEffect(() => {
    refresh();
    const unlistenProgress = listen<DownloadProgress>("download-progress", (event) => {
      setProgressById((prev) => ({ ...prev, [event.payload.download_id]: event.payload }));
    });
    const unlistenComplete = listen("download-complete", refresh);
    const unlistenError = listen("download-error", refresh);
    return () => {
      unlistenProgress.then((fn) => fn());
      unlistenComplete.then((fn) => fn());
      unlistenError.then((fn) => fn());
    };
  }, []);

  async function togglePause(id: number) {
    if (pausedIds.has(id)) {
      await api.resumeDownload(id);
      setPausedIds((prev) => {
        const next = new Set(prev);
        next.delete(id);
        return next;
      });
    } else {
      await api.pauseDownload(id);
      setPausedIds((prev) => new Set(prev).add(id));
    }
  }

  async function cancel(id: number) {
    await api.cancelDownload(id);
    refresh();
  }

  if (downloads.length === 0) {
    return (
      <div className="flex h-full items-center justify-center pt-11 text-sm text-muted-foreground">
        {t("queue.empty")}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3 overflow-y-auto p-6 pt-14">
      {downloads.map((d) => {
        const progress = progressById[d.id];
        const percent = progress ? parseFloat(progress.percent) || 0 : 0;
        const isPaused = pausedIds.has(d.id);
        return (
          <div key={d.id} className="flex flex-col gap-2 rounded-lg border border-border p-3">
            <div className="flex items-center justify-between gap-2">
              <p className="min-w-0 flex-1 truncate text-sm font-medium">{d.title}</p>
              <div className="flex gap-1">
                <Button size="icon" variant="ghost" onClick={() => togglePause(d.id)}>
                  {isPaused ? <Play className="size-4" /> : <Pause className="size-4" />}
                </Button>
                <Button size="icon" variant="ghost" onClick={() => cancel(d.id)}>
                  <X className="size-4" />
                </Button>
              </div>
            </div>
            <Progress value={percent} />
            <div className="flex justify-between text-xs text-muted-foreground">
              <span>{progress?.percent?.trim() || "0%"}</span>
              <span>{progress?.speed?.trim() ?? ""}</span>
              <span>{progress?.eta?.trim() ? t("queue.eta", { eta: progress.eta.trim() }) : ""}</span>
            </div>
          </div>
        );
      })}
    </div>
  );
}
