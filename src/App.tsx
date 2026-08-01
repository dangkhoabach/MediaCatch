import { useEffect } from "react";
import { ThemeProvider, useTheme } from "next-themes";
import { HashRouter, Route, Routes, useNavigate } from "react-router";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { Toaster } from "@/components/ui/sonner";
import { Sidebar } from "@/components/layout/Sidebar";
import { UpdateDialog } from "@/components/layout/UpdateDialog";
import { HomePage } from "@/pages/Home";
import { QueuePage } from "@/pages/Queue";
import { LibraryPage } from "@/pages/Library";
import { WatchPage } from "@/pages/Watch";
import { SettingsPage } from "@/pages/Settings";
import { LanguageProvider, useTranslation } from "@/lib/i18n/context";
import { HomeStateProvider } from "@/lib/home-state";
import { api } from "@/lib/api";
import { getNotificationsEnabled } from "@/lib/settings";

/// The macOS vibrancy blur is a native window-level effect, not CSS — it
/// must be told the resolved theme separately or it keeps rendering with
/// whatever appearance the window started with, regardless of the in-app
/// theme toggle.
function NativeThemeSync() {
  const { theme } = useTheme();

  useEffect(() => {
    // Pass the user's selected mode, not the resolved value — when it's
    // "system", the native window must keep tracking OS appearance changes
    // itself rather than being pinned to whatever it resolved to right now.
    if (theme) {
      invoke("set_native_theme", { theme }).catch(() => {});
    }
  }, [theme]);

  return null;
}

/// Backend's notification.rs emits this once the user clicks a native
/// notification (after already bringing the window forward) — this just
/// finishes the job by routing to the page the notification was about.
/// Must live inside <HashRouter> since useNavigate() needs router context.
function NotificationNavigator() {
  const navigate = useNavigate();

  useEffect(() => {
    const unlisten = listen<string>("notification-clicked", (event) => {
      navigate(event.payload);
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, [navigate]);

  return null;
}

/// Notifications live behind the frontend's own "Notifications" toggle (see
/// settings.ts), not a Rust-side setting — Rust just exposes a generic
/// show_notification command, and this is the one place that decides
/// whether to call it, for both download outcomes and yt-dlp self-updates.
function DownloadNotifications() {
  const { t } = useTranslation();

  useEffect(() => {
    async function notifyForDownload(id: number, titleKey: "notification.downloadComplete.title" | "notification.downloadError.title") {
      if (!getNotificationsEnabled()) return;
      try {
        const downloads = await api.listDownloads();
        const record = downloads.find((d) => d.id === id);
        await invoke("show_notification", {
          title: t(titleKey),
          body: record?.title ?? "",
          route: "/library",
        });
      } catch {
        // best-effort — a failed notification shouldn't surface as an error
      }
    }

    const unlistenComplete = listen<number>("download-complete", (event) =>
      notifyForDownload(event.payload, "notification.downloadComplete.title"),
    );
    const unlistenError = listen<number>("download-error", (event) =>
      notifyForDownload(event.payload, "notification.downloadError.title"),
    );
    return () => {
      unlistenComplete.then((fn) => fn());
      unlistenError.then((fn) => fn());
    };
  }, [t]);

  return null;
}

/// Watched channels/playlists are polled entirely in Rust (see watch.rs) —
/// this just turns each "found a new upload" event into a native
/// notification, gated by the same frontend-owned toggle as everything else.
function WatchNotifications() {
  const { t } = useTranslation();

  useEffect(() => {
    const unlisten = listen<{ channelTitle: string; videoTitle: string }>(
      "watched-new-video",
      (event) => {
        if (!getNotificationsEnabled()) return;
        invoke("show_notification", {
          title: t("notification.watchedNewVideo.title", { channel: event.payload.channelTitle }),
          body: event.payload.videoTitle,
          route: "/queue",
        }).catch(() => {});
      },
    );
    return () => {
      unlisten.then((fn) => fn());
    };
  }, [t]);

  return null;
}

/// Checks for a newer yt-dlp release once per app launch — independent of
/// this app's own update cycle (see ytdlp.rs's update_ytdlp).
function YtdlpUpdateChecker() {
  const { t } = useTranslation();

  useEffect(() => {
    api
      .updateYtdlp()
      .then((newVersion) => {
        if (!newVersion || !getNotificationsEnabled()) return;
        return invoke("show_notification", {
          title: t("notification.ytdlpUpdated.title"),
          body: t("notification.ytdlpUpdated.body", { version: newVersion }),
          route: null,
        });
      })
      .catch(() => {
        // offline or GitHub unreachable — silently keep using the current binary
      });
  }, [t]);

  return null;
}

/// Cmd+, is the standard macOS convention for opening an app's settings.
function KeyboardShortcuts() {
  const navigate = useNavigate();

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key === ",") {
        e.preventDefault();
        navigate("/settings");
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [navigate]);

  return null;
}

function App() {
  return (
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
      <NativeThemeSync />
      <LanguageProvider>
        <HomeStateProvider>
          <DownloadNotifications />
          <WatchNotifications />
          <YtdlpUpdateChecker />
          <UpdateDialog />
          <HashRouter>
            <NotificationNavigator />
            <KeyboardShortcuts />
            <div className="flex h-screen text-foreground">
              <div data-tauri-drag-region className="fixed inset-x-0 top-0 z-30 h-11" />
              <Sidebar />
              <main className="flex flex-1 flex-col overflow-hidden">
                <Routes>
                  <Route path="/" element={<HomePage />} />
                  <Route path="/queue" element={<QueuePage />} />
                  <Route path="/library" element={<LibraryPage />} />
                  <Route path="/watch" element={<WatchPage />} />
                  <Route path="/settings" element={<SettingsPage />} />
                </Routes>
              </main>
              <Toaster />
            </div>
          </HashRouter>
        </HomeStateProvider>
      </LanguageProvider>
    </ThemeProvider>
  );
}

export default App;
