import { useState, type DragEvent } from "react";
import { useNavigate } from "react-router";
import { toast } from "sonner";
import { Loader2, Music, Video } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { api } from "@/lib/api";
import { ensureOutputDir, getOutputFormat } from "@/lib/settings";
import { useTranslation } from "@/lib/i18n/context";
import type { VideoInfo } from "@/types/download";

function formatSize(bytes: number | null): string {
  if (!bytes) return "—";
  const mb = bytes / (1024 * 1024);
  return mb > 1024 ? `${(mb / 1024).toFixed(2)} GB` : `${mb.toFixed(1)} MB`;
}

function formatDuration(seconds: number | null): string {
  if (!seconds) return "—";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export function HomePage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const [url, setUrl] = useState("");
  const [loading, setLoading] = useState(false);
  const [info, setInfo] = useState<VideoInfo | null>(null);
  const [selectedFormatId, setSelectedFormatId] = useState<string | null>(null);
  const [audioOnly, setAudioOnly] = useState(false);
  const [starting, setStarting] = useState(false);

  async function handleFetchInfo(overrideUrl?: string) {
    const trimmed = (overrideUrl ?? url).trim();
    if (!trimmed) return;
    setLoading(true);
    setInfo(null);
    setSelectedFormatId(null);
    try {
      const result = await api.fetchVideoInfo(trimmed);
      setInfo(result);
      const best = [...result.formats]
        .filter((f) => f.has_video)
        .sort((a, b) => (b.height ?? 0) - (a.height ?? 0))[0];
      setSelectedFormatId(best?.format_id ?? null);
    } catch (e) {
      toast.error(t("home.fetchError"), { description: String(e) });
    } finally {
      setLoading(false);
    }
  }

  async function handleDownload() {
    if (!info) return;
    setStarting(true);
    try {
      const outputDir = await ensureOutputDir();
      const outputFormat = getOutputFormat();
      let selector: string;
      if (audioOnly) {
        selector = "bestaudio/best";
      } else {
        const format = info.formats.find((f) => f.format_id === selectedFormatId);
        if (!format) throw new Error(t("home.noFormatSelected"));
        selector = format.has_audio ? format.format_id : `${format.format_id}+bestaudio/best`;
      }
      await api.startDownload(url.trim(), info.title, selector, outputDir, outputFormat);
      toast.success(t("home.downloadStarted"), { description: info.title });
      navigate("/queue");
    } catch (e) {
      toast.error(t("home.downloadStartError"), { description: String(e) });
    } finally {
      setStarting(false);
    }
  }

  function handleDrop(e: DragEvent<HTMLDivElement>) {
    e.preventDefault();
    const dropped = e.dataTransfer.getData("text/uri-list") || e.dataTransfer.getData("text/plain");
    if (!dropped) return;
    setUrl(dropped);
    handleFetchInfo(dropped);
  }

  const videoFormats = (info?.formats ?? [])
    .filter((f) => f.has_video)
    .sort((a, b) => (b.height ?? 0) - (a.height ?? 0));

  return (
    <div
      className="flex h-full flex-col gap-4 overflow-y-auto p-6 pt-14"
      onDragOver={(e) => e.preventDefault()}
      onDrop={handleDrop}
    >
      <div className="flex gap-2">
        <Input
          placeholder={t("home.urlPlaceholder")}
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handleFetchInfo()}
        />
        <Button onClick={() => handleFetchInfo()} disabled={loading || !url.trim()}>
          {loading ? <Loader2 className="size-4 animate-spin" /> : t("home.fetchInfo")}
        </Button>
      </div>

      {info && (
        <div className="flex flex-col gap-4">
          <div className="flex gap-3">
            {info.thumbnail && (
              <img src={info.thumbnail} alt="" className="h-24 w-40 rounded-md object-cover" />
            )}
            <div className="flex flex-col justify-center gap-1">
              <p className="text-sm font-medium">{info.title}</p>
              <p className="text-xs text-muted-foreground">{formatDuration(info.duration)}</p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <Switch checked={audioOnly} onCheckedChange={setAudioOnly} id="audio-only" />
            <Label htmlFor="audio-only" className="flex items-center gap-1.5 text-sm">
              <Music className="size-3.5" /> {t("home.audioOnly")}
            </Label>
          </div>

          {!audioOnly && (
            <div className="flex flex-col overflow-hidden rounded-lg border border-border">
              {videoFormats.map((f) => (
                <label
                  key={f.format_id}
                  className="flex cursor-pointer items-center gap-3 border-b border-border px-3 py-2 text-sm last:border-b-0 hover:bg-accent/50"
                >
                  <input
                    type="radio"
                    name="format"
                    checked={selectedFormatId === f.format_id}
                    onChange={() => setSelectedFormatId(f.format_id)}
                  />
                  <Video className="size-3.5 text-muted-foreground" />
                  <span className="w-14 font-medium">{f.height ? `${f.height}p` : "—"}</span>
                  <span className="w-16 text-muted-foreground">{f.fps ? `${f.fps}fps` : ""}</span>
                  <span className="w-20 uppercase text-muted-foreground">{f.vcodec}</span>
                  <span className="w-20 text-muted-foreground">
                    {f.has_audio ? t("home.hasAudio") : t("home.noAudio")}
                  </span>
                  <span className="ml-auto text-muted-foreground">{formatSize(f.filesize)}</span>
                </label>
              ))}
            </div>
          )}

          <Button onClick={handleDownload} disabled={starting} className="self-start">
            {starting ? <Loader2 className="size-4 animate-spin" /> : t("home.download")}
          </Button>
        </div>
      )}
    </div>
  );
}
