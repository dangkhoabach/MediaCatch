import { useState } from "react";
import { open } from "@tauri-apps/plugin-dialog";
import { FolderOpen } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { getOutputDir, getOutputFormat, setOutputDir, setOutputFormat, type OutputFormat } from "@/lib/settings";

export function SettingsPage() {
  const [outputDir, setOutputDirState] = useState(getOutputDir());
  const [outputFormat, setOutputFormatState] = useState<OutputFormat>(getOutputFormat());

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

  return (
    <div className="flex flex-col gap-6 overflow-y-auto p-6 pt-14">
      <div className="flex flex-col gap-2">
        <Label htmlFor="output-dir">Thư mục lưu mặc định</Label>
        <div className="flex gap-2">
          <Input id="output-dir" value={outputDir} readOnly />
          <Button variant="outline" size="icon" onClick={handleBrowse}>
            <FolderOpen className="size-4" />
          </Button>
        </div>
      </div>

      <div className="flex flex-col gap-2">
        <Label>Định dạng output mặc định</Label>
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
    </div>
  );
}
