import { useState } from "react";
import { useTheme } from "next-themes";
import { open } from "@tauri-apps/plugin-dialog";
import { invoke } from "@tauri-apps/api/core";
import { toast } from "sonner";
import { FolderOpen, Monitor, Moon, Sun } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { cn } from "@/lib/utils";
import { useTranslation } from "@/lib/i18n/context";
import {
  getNotificationsEnabled,
  getOutputDir,
  getOutputFormat,
  setNotificationsEnabled,
  setOutputDir,
  setOutputFormat,
  type OutputFormat,
} from "@/lib/settings";

const THEME_OPTIONS = [
  { value: "light", icon: Sun, labelKey: "settings.theme.light" as const },
  { value: "dark", icon: Moon, labelKey: "settings.theme.dark" as const },
  { value: "system", icon: Monitor, labelKey: "settings.theme.system" as const },
];

function segmentClass(selected: boolean) {
  return cn(
    "flex h-7 flex-1 items-center justify-center gap-1.5 rounded-md px-2 text-xs leading-none font-medium transition-colors",
    selected
      ? "bg-white text-foreground shadow-sm dark:bg-white/20"
      : "text-muted-foreground hover:text-foreground",
  );
}

export function SettingsPage() {
  const { t, locale, setLocale } = useTranslation();
  const { theme, setTheme } = useTheme();
  const [outputDir, setOutputDirState] = useState(getOutputDir());
  const [outputFormat, setOutputFormatState] = useState<OutputFormat>(getOutputFormat());
  const [notificationsEnabled, setNotificationsEnabledState] = useState(getNotificationsEnabled());

  async function handleBrowse() {
    const selected = await open({ directory: true, defaultPath: outputDir || undefined });
    if (typeof selected === "string") {
      setOutputDirState(selected);
      setOutputDir(selected);
    }
  }

  function handleFormatChange(value: string | null) {
    if (!value) return;
    const format = value as OutputFormat;
    setOutputFormatState(format);
    setOutputFormat(format);
  }

  function handleNotificationsToggle(checked: boolean) {
    setNotificationsEnabledState(checked);
    setNotificationsEnabled(checked);
    if (checked) {
      // There's no reliable way to read the real macOS permission state from
      // here, so this fires a real notification — which triggers the native
      // permission prompt on first use — and always offers a direct link to
      // this app's Notifications settings pane either way.
      invoke("show_notification", {
        title: t("app.name"),
        body: t("settings.notificationsHint"),
        route: null,
      }).catch(() => {});
      toast.info(t("settings.notificationsPermissionHint"), {
        action: {
          label: t("settings.openSettings"),
          onClick: () => invoke("open_notification_settings").catch(() => {}),
        },
      });
    }
  }

  return (
    <div className="flex flex-col gap-6 overflow-y-auto p-6 pt-14">
      <div className="flex flex-col gap-2">
        <Label htmlFor="output-dir">{t("settings.outputDir")}</Label>
        <div className="flex gap-2">
          <Input id="output-dir" value={outputDir} readOnly />
          <Button variant="outline" size="icon" onClick={handleBrowse}>
            <FolderOpen className="size-4" />
          </Button>
        </div>
      </div>

      <div className="flex flex-col gap-2">
        <Label>{t("settings.outputFormat")}</Label>
        <Select value={outputFormat} onValueChange={handleFormatChange}>
          <SelectTrigger className="w-40">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="mp4">MP4</SelectItem>
            <SelectItem value="mkv">MKV</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="flex items-center justify-between">
        <span className="text-sm">{t("settings.theme")}</span>
        <div className="flex items-center gap-0.5 rounded-lg bg-black/[0.06] p-0.5 dark:bg-white/10">
          {THEME_OPTIONS.map(({ value, icon: Icon, labelKey }) => (
            <button key={value} onClick={() => setTheme(value)} className={segmentClass(theme === value)}>
              <Icon className="size-3.5" />
              {t(labelKey)}
            </button>
          ))}
        </div>
      </div>

      <div className="flex items-center justify-between">
        <span className="text-sm">{t("settings.language")}</span>
        <div className="flex items-center gap-0.5 rounded-lg bg-black/[0.06] p-0.5 dark:bg-white/10">
          <button onClick={() => setLocale("vi")} className={segmentClass(locale === "vi")}>
            VI
          </button>
          <button onClick={() => setLocale("en")} className={segmentClass(locale === "en")}>
            EN
          </button>
        </div>
      </div>

      <div className="flex items-center justify-between">
        <div className="flex flex-col">
          <span className="text-sm">{t("settings.notifications")}</span>
          <span className="text-xs text-muted-foreground">{t("settings.notificationsHint")}</span>
        </div>
        <Switch checked={notificationsEnabled} onCheckedChange={handleNotificationsToggle} />
      </div>
    </div>
  );
}
