import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

// TEMPORARY Phase 1 verification harness — exercises fetch_video_info /
// start_download directly to prove the yt-dlp engine works end-to-end.
// Replaced by the real UI in Phase 2.
function App() {
  const [url, setUrl] = useState("https://www.youtube.com/watch?v=aqz-KE-bpKQ");
  const [formatSelector, setFormatSelector] = useState("bestvideo+bestaudio/best");
  const [log, setLog] = useState("");
  const [progress, setProgress] = useState("");

  async function testFetchInfo() {
    setLog("fetching...");
    try {
      const info = await invoke("fetch_video_info", { url });
      setLog(JSON.stringify(info, null, 2));
    } catch (e) {
      setLog("ERROR: " + String(e));
    }
  }

  async function testDownload() {
    setLog("starting download...");
    try {
      const unlistenProgress = await listen<{ percent: string; speed: string; eta: string }>(
        "download-progress",
        (event) => setProgress(JSON.stringify(event.payload)),
      );
      const unlistenComplete = await listen("download-complete", () => {
        setProgress("DONE");
        unlistenProgress();
        unlistenComplete();
      });
      const id = await invoke("start_download", {
        url,
        title: "test",
        formatSelector,
        outputDir: "/Users/dangkhoabach/Downloads",
      });
      setLog("download id: " + id);
    } catch (e) {
      setLog("ERROR: " + String(e));
    }
  }

  return (
    <div className="flex h-screen flex-col gap-3 overflow-auto p-6 pt-14 text-foreground">
      <div data-tauri-drag-region className="fixed inset-x-0 top-0 z-30 h-11" />
      <input
        className="rounded border border-border bg-transparent px-2 py-1 text-sm"
        value={url}
        onChange={(e) => setUrl(e.target.value)}
      />
      <input
        className="rounded border border-border bg-transparent px-2 py-1 text-sm"
        value={formatSelector}
        onChange={(e) => setFormatSelector(e.target.value)}
      />
      <div className="flex gap-2">
        <button className="rounded bg-primary px-3 py-1 text-sm text-primary-foreground" onClick={testFetchInfo}>
          Fetch Info
        </button>
        <button className="rounded bg-primary px-3 py-1 text-sm text-primary-foreground" onClick={testDownload}>
          Download
        </button>
      </div>
      <p className="text-xs text-muted-foreground">{progress}</p>
      <pre className="whitespace-pre-wrap text-xs">{log}</pre>
    </div>
  );
}

export default App;
