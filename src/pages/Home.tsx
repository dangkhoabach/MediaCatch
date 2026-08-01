import type { DragEvent } from "react";
import { useNavigate } from "react-router";
import { toast } from "sonner";
import { CheckCircle2, Image as ImageIcon, Loader2, Music, Video, XCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { api } from "@/lib/api";
import { ensureOutputDir, getEmbedMetadata, getOutputFormat } from "@/lib/settings";
import { useTranslation } from "@/lib/i18n/context";
import { useHomeState } from "@/lib/home-state";

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

const PLATFORM_PATTERNS: [RegExp, string][] = [
  [/(^|\.)youtube\.com$|^youtu\.be$/, "YouTube"],
  [/(^|\.)facebook\.com$|^fb\.watch$/, "Facebook"],
  [/(^|\.)instagram\.com$/, "Instagram"],
  [/(^|\.)tiktok\.com$/, "TikTok"],
  [/(^|\.)twitter\.com$|^x\.com$/, "Twitter/X"],
];

/** yt-dlp already handles extraction for all of these — this is purely a UI label, no backend difference. */
function detectPlatform(rawUrl: string): string | null {
  try {
    const host = new URL(rawUrl).hostname.toLowerCase();
    return PLATFORM_PATTERNS.find(([pattern]) => pattern.test(host))?.[1] ?? null;
  } catch {
    return null;
  }
}

/**
 * Only recognizes unambiguous, YouTube-only playlist links (a bare
 * `/playlist?list=...` or `list=` without an accompanying `v=`) — the
 * platform we've actually verified this against. A `watch?v=X&list=Y` link
 * (very common when the video being watched happens to be part of a
 * playlist) is deliberately NOT treated as a playlist: that link's intent is
 * almost always "this one video", matching fetch_video_info's existing
 * --no-playlist behavior. Other platforms fall through to the normal
 * single-link flow rather than guessing at their playlist URL shapes.
 */
function isPlaylistUrl(rawUrl: string): boolean {
  try {
    const u = new URL(rawUrl);
    const host = u.hostname.toLowerCase();
    if (!/(^|\.)youtube\.com$/.test(host)) return false;
    return u.searchParams.has("list") && !u.searchParams.has("v");
  } catch {
    return false;
  }
}

export function HomePage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const {
    url,
    setUrl,
    loading,
    setLoading,
    info,
    setInfo,
    platform,
    setPlatform,
    selectedFormatId,
    setSelectedFormatId,
    audioOnly,
    setAudioOnly,
    starting,
    setStarting,
    batchMode,
    setBatchMode,
    batchText,
    setBatchText,
    batchItems,
    setBatchItems,
    batchRunning,
    setBatchRunning,
  } = useHomeState();

  async function handleExpandPlaylist(playlistUrl: string) {
    setLoading(true);
    try {
      const entries = await api.expandPlaylist(playlistUrl);
      if (entries.length === 0) throw new Error(t("home.playlistEmpty"));
      setBatchMode(true);
      setBatchItems([]);
      setBatchText(entries.map((e) => e.url).join("\n"));
      toast.success(t("home.playlistExpanded", { count: entries.length }));
    } catch (e) {
      toast.error(t("home.playlistExpandError"), { description: String(e) });
    } finally {
      setLoading(false);
    }
  }

  async function handleFetchInfo(overrideUrl?: string) {
    const trimmed = (overrideUrl ?? url).trim();
    if (!trimmed) return;
    if (isPlaylistUrl(trimmed)) {
      await handleExpandPlaylist(trimmed);
      return;
    }
    setLoading(true);
    setInfo(null);
    setPlatform(detectPlatform(trimmed));
    setSelectedFormatId(null);
    try {
      const result = await api.fetchVideoInfo(trimmed);
      setInfo(result);
      if (audioOnly) {
        const bestAudio = [...result.formats]
          .filter((f) => f.has_audio && !f.has_video)
          .sort((a, b) => (b.tbr ?? 0) - (a.tbr ?? 0))[0];
        setSelectedFormatId(bestAudio?.format_id ?? null);
      } else {
        const bestVideo = [...result.formats]
          .filter((f) => f.has_video)
          .sort((a, b) => (b.height ?? 0) - (a.height ?? 0))[0];
        const bestImage = [...result.formats]
          .filter((f) => !f.has_video && !f.has_audio)
          .sort((a, b) => (b.filesize ?? 0) - (a.filesize ?? 0))[0];
        setSelectedFormatId(bestVideo?.format_id ?? bestImage?.format_id ?? null);
      }
    } catch (e) {
      toast.error(t("home.fetchError"), { description: String(e) });
    } finally {
      setLoading(false);
    }
  }

  function handleAudioOnlyToggle(checked: boolean) {
    setAudioOnly(checked);
    if (!info) return;
    if (checked) {
      const bestAudio = [...info.formats]
        .filter((f) => f.has_audio && !f.has_video)
        .sort((a, b) => (b.tbr ?? 0) - (a.tbr ?? 0))[0];
      setSelectedFormatId(bestAudio?.format_id ?? null);
    } else {
      const bestVideo = [...info.formats]
        .filter((f) => f.has_video)
        .sort((a, b) => (b.height ?? 0) - (a.height ?? 0))[0];
      setSelectedFormatId(bestVideo?.format_id ?? null);
    }
  }

  async function handleDownload() {
    if (!info) return;
    setStarting(true);
    try {
      const outputDir = await ensureOutputDir();
      const outputFormat = getOutputFormat();
      const format = info.formats.find((f) => f.format_id === selectedFormatId);
      if (!format) throw new Error(t("home.noFormatSelected"));
      // A format with no video track is already a complete standalone asset
      // on its own — an audio-only track, or (neither video nor audio) a
      // photo post — no audio to merge in either way.
      const selector = !format.has_video
        ? format.format_id
        : format.has_audio
          ? format.format_id
          : `${format.format_id}+bestaudio/best`;
      await api.startDownload(
        url.trim(),
        info.title,
        selector,
        outputDir,
        outputFormat,
        getEmbedMetadata(),
      );
      toast.success(t("home.downloadStarted"), { description: info.title });
      navigate("/queue");
    } catch (e) {
      toast.error(t("home.downloadStartError"), { description: String(e) });
    } finally {
      setStarting(false);
    }
  }

  async function handleBatchSubmit() {
    const urls = Array.from(
      new Set(
        batchText
          .split("\n")
          .map((line) => line.trim())
          .filter(Boolean),
      ),
    );
    if (urls.length === 0) return;

    setBatchRunning(true);
    setBatchItems(urls.map((itemUrl) => ({ url: itemUrl, status: "pending" })));

    const outputDir = await ensureOutputDir();
    const outputFormat = getOutputFormat();
    const embedMetadata = getEmbedMetadata();
    let successCount = 0;

    for (let i = 0; i < urls.length; i++) {
      const itemUrl = urls[i];
      setBatchItems((prev) => prev.map((item, idx) => (idx === i ? { ...item, status: "working" } : item)));
      try {
        const result = await api.fetchVideoInfo(itemUrl);
        let selector: string;
        if (audioOnly) {
          selector = "bestaudio/best";
        } else {
          const best = [...result.formats]
            .filter((f) => f.has_video)
            .sort((a, b) => (b.height ?? 0) - (a.height ?? 0))[0];
          if (!best) throw new Error(t("home.noFormatSelected"));
          selector = best.has_audio ? best.format_id : `${best.format_id}+bestaudio/best`;
        }
        await api.startDownload(itemUrl, result.title, selector, outputDir, outputFormat, embedMetadata);
        successCount++;
        setBatchItems((prev) =>
          prev.map((item, idx) => (idx === i ? { ...item, status: "done", message: result.title } : item)),
        );
      } catch (e) {
        setBatchItems((prev) =>
          prev.map((item, idx) => (idx === i ? { ...item, status: "error", message: String(e) } : item)),
        );
      }
    }

    setBatchRunning(false);
    if (successCount > 0) {
      toast.success(t("home.batchSummary", { success: successCount, total: urls.length }));
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

  // Neither video nor audio codec — a standalone asset (photo posts on
  // Instagram/Twitter etc. show up this way), not a quality tier of a video.
  const imageFormats = (info?.formats ?? [])
    .filter((f) => !f.has_video && !f.has_audio)
    .sort((a, b) => (b.filesize ?? 0) - (a.filesize ?? 0));

  const audioFormats = (info?.formats ?? [])
    .filter((f) => f.has_audio && !f.has_video)
    .sort((a, b) => (b.tbr ?? 0) - (a.tbr ?? 0));

  return (
    <div
      className="flex h-full flex-col gap-4 overflow-y-auto p-6 pt-14"
      onDragOver={(e) => e.preventDefault()}
      onDrop={handleDrop}
    >
      {batchMode ? (
        <Textarea
          placeholder={t("home.batchPlaceholder")}
          value={batchText}
          onChange={(e) => setBatchText(e.target.value)}
          className="min-h-32"
        />
      ) : (
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
      )}

      <div className="flex items-center gap-2 self-end">
        <Switch
          checked={batchMode}
          onCheckedChange={(checked) => {
            setBatchMode(checked);
            setBatchItems([]);
          }}
          id="batch-mode"
        />
        <Label htmlFor="batch-mode" className="text-sm text-muted-foreground">
          {t("home.batchMode")}
        </Label>
      </div>

      {batchMode ? (
        <div className="flex flex-col gap-4">
          <div className="flex items-center gap-2">
            <Switch checked={audioOnly} onCheckedChange={setAudioOnly} id="batch-audio-only" />
            <Label htmlFor="batch-audio-only" className="flex items-center gap-1.5 text-sm">
              <Music className="size-3.5" /> {t("home.audioOnly")}
            </Label>
          </div>

          <Button onClick={handleBatchSubmit} disabled={batchRunning || !batchText.trim()} className="self-start">
            {batchRunning ? <Loader2 className="size-4 animate-spin" /> : t("home.batchSubmit")}
          </Button>

          {batchItems.length > 0 && (
            <div className="flex flex-col overflow-hidden rounded-lg border border-border">
              {batchItems.map((item, i) => (
                <div
                  key={i}
                  className="flex items-center gap-2 border-b border-border px-3 py-2 text-sm last:border-b-0"
                >
                  {item.status === "pending" && (
                    <span className="size-3.5 rounded-full border border-muted-foreground/40" />
                  )}
                  {item.status === "working" && (
                    <Loader2 className="size-3.5 shrink-0 animate-spin text-muted-foreground" />
                  )}
                  {item.status === "done" && <CheckCircle2 className="size-3.5 shrink-0 text-green-600" />}
                  {item.status === "error" && <XCircle className="size-3.5 shrink-0 text-destructive" />}
                  <span className="flex-1 truncate">{item.message ?? item.url}</span>
                </div>
              ))}
            </div>
          )}

          {!batchRunning && batchItems.length > 0 && (
            <Button variant="outline" onClick={() => navigate("/queue")} className="self-start">
              {t("nav.queue")}
            </Button>
          )}
        </div>
      ) : (
        <>
          {info && (
            <div className="flex flex-col gap-4">
              <div className="flex gap-3">
                {info.thumbnail && (
                  <img src={info.thumbnail} alt="" className="h-24 w-40 rounded-md object-cover" />
                )}
                <div className="flex flex-col justify-center gap-1">
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium">{info.title}</p>
                    {platform && <Badge variant="outline">{platform}</Badge>}
                  </div>
                  <p className="text-xs text-muted-foreground">{formatDuration(info.duration)}</p>
                </div>
              </div>

              {videoFormats.length > 0 && (
                <div className="flex items-center gap-2">
                  <Switch checked={audioOnly} onCheckedChange={handleAudioOnlyToggle} id="audio-only" />
                  <Label htmlFor="audio-only" className="flex items-center gap-1.5 text-sm">
                    <Music className="size-3.5" /> {t("home.audioOnly")}
                  </Label>
                </div>
              )}

              {audioOnly && audioFormats.length > 0 && (
                <div className="flex flex-col overflow-hidden rounded-lg border border-border">
                  {audioFormats.map((f) => (
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
                      <Music className="size-3.5 shrink-0 text-muted-foreground" />
                      <span className="w-20 shrink-0 font-medium">{f.tbr ? `${Math.round(f.tbr)}kbps` : "—"}</span>
                      <span className="w-16 shrink-0 uppercase text-muted-foreground" title={f.acodec}>
                        {f.ext}
                      </span>
                      <span className="ml-auto shrink-0 text-muted-foreground">{formatSize(f.filesize)}</span>
                    </label>
                  ))}
                </div>
              )}

              {!audioOnly && videoFormats.length > 0 && (
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
                      <Video className="size-3.5 shrink-0 text-muted-foreground" />
                      <span className="w-14 shrink-0 font-medium">{f.height ? `${f.height}p` : "—"}</span>
                      <span className="w-14 shrink-0 text-muted-foreground">{f.fps ? `${f.fps}fps` : ""}</span>
                      <span
                        className="w-24 shrink-0 truncate uppercase text-muted-foreground"
                        title={f.vcodec}
                      >
                        {f.vcodec}
                      </span>
                      <span className="w-20 shrink-0 text-muted-foreground">
                        {f.has_audio ? t("home.hasAudio") : t("home.noAudio")}
                      </span>
                      <span className="ml-auto shrink-0 text-muted-foreground">{formatSize(f.filesize)}</span>
                    </label>
                  ))}
                </div>
              )}

              {videoFormats.length === 0 && imageFormats.length > 0 && (
                <div className="flex flex-col overflow-hidden rounded-lg border border-border">
                  {imageFormats.map((f) => (
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
                      <ImageIcon className="size-3.5 text-muted-foreground" />
                      <span className="w-16 uppercase text-muted-foreground">{f.ext}</span>
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
        </>
      )}
    </div>
  );
}
