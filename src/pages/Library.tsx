import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { openPath, revealItemInDir } from "@tauri-apps/plugin-opener";
import { FolderOpen, Play, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { api } from "@/lib/api";
import { useTranslation } from "@/lib/i18n/context";
import type { DownloadRecord } from "@/types/download";
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

export function LibraryPage() {
  const { t } = useTranslation();
  const [records, setRecords] = useState<DownloadRecord[]>([]);

  async function refresh() {
    try {
      const all = await api.listDownloads();
      setRecords(all.filter((d) => d.status !== "downloading"));
    } catch {
      // keep previous list on transient failure
    }
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

  if (records.length === 0) {
    return (
      <div className="flex h-full items-center justify-center pt-11 text-sm text-muted-foreground">
        {t("library.empty")}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2 overflow-y-auto p-6 pt-14">
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
  );
}
