export interface VideoFormat {
  format_id: string;
  ext: string;
  height: number | null;
  fps: number | null;
  vcodec: string;
  acodec: string;
  has_video: boolean;
  has_audio: boolean;
  filesize: number | null;
  tbr: number | null;
  format_note: string | null;
}

export interface VideoInfo {
  id: string;
  title: string;
  thumbnail: string | null;
  duration: number | null;
  formats: VideoFormat[];
}

export interface DownloadRecord {
  id: number;
  url: string;
  title: string;
  format_selector: string;
  output_dir: string;
  output_path: string | null;
  status: "downloading" | "completed" | "error" | "canceled";
  error_message: string | null;
  created_at: string;
}

export interface DownloadProgress {
  download_id: number;
  percent: string;
  speed: string;
  eta: string;
}
