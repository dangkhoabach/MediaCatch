import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Loader2, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { api } from "@/lib/api";
import { ensureOutputDir, getOutputFormat } from "@/lib/settings";
import { useTranslation } from "@/lib/i18n/context";
import type { WatchedChannel } from "@/types/download";

export function WatchPage() {
  const { t } = useTranslation();
  const [channels, setChannels] = useState<WatchedChannel[]>([]);
  const [url, setUrl] = useState("");
  const [adding, setAdding] = useState(false);

  async function refresh() {
    try {
      setChannels(await api.listWatchedChannels());
    } catch {
      // keep previous list on transient failure
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  async function handleAdd() {
    const trimmed = url.trim();
    if (!trimmed) return;
    setAdding(true);
    try {
      const outputDir = await ensureOutputDir();
      const outputFormat = getOutputFormat();
      await api.addWatchedChannel(trimmed, outputDir, outputFormat);
      setUrl("");
      await refresh();
      toast.success(t("watch.added"));
    } catch (e) {
      toast.error(t("watch.addError"), { description: String(e) });
    } finally {
      setAdding(false);
    }
  }

  async function handleToggle(id: number, enabled: boolean) {
    setChannels((prev) => prev.map((c) => (c.id === id ? { ...c, enabled } : c)));
    try {
      await api.setWatchedChannelEnabled(id, enabled);
    } catch (e) {
      toast.error(t("watch.toggleError"), { description: String(e) });
      refresh();
    }
  }

  async function handleRemove(id: number) {
    try {
      await api.removeWatchedChannel(id);
      refresh();
    } catch (e) {
      toast.error(t("watch.removeError"), { description: String(e) });
    }
  }

  return (
    <div className="flex flex-col gap-4 overflow-y-auto p-6 pt-14">
      <div className="flex gap-2">
        <Input
          placeholder={t("watch.urlPlaceholder")}
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handleAdd()}
        />
        <Button onClick={handleAdd} disabled={adding || !url.trim()}>
          {adding ? <Loader2 className="size-4 animate-spin" /> : t("watch.add")}
        </Button>
      </div>

      {channels.length === 0 ? (
        <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
          {t("watch.empty")}
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          {channels.map((c) => (
            <div key={c.id} className="flex items-center gap-3 rounded-lg border border-border p-3">
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{c.title}</p>
                <p className="truncate text-xs text-muted-foreground">
                  {c.last_checked_at
                    ? t("watch.lastChecked", { time: new Date(c.last_checked_at + "Z").toLocaleString() })
                    : t("watch.neverChecked")}
                </p>
              </div>
              <Switch checked={c.enabled} onCheckedChange={(checked) => handleToggle(c.id, checked)} />
              <Button size="icon" variant="ghost" onClick={() => handleRemove(c.id)}>
                <Trash2 className="size-4" />
              </Button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
