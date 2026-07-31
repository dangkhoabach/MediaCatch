use serde::{Deserialize, Serialize};

/// Subset of yt-dlp's `-j` (dump-json) output we actually use — its real
/// schema has hundreds of extractor-dependent fields, so this only lists
/// what the UI needs rather than mirroring it in full.
#[derive(Deserialize)]
pub struct YtDlpInfo {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub thumbnail: Option<String>,
    #[serde(default)]
    pub duration: Option<f64>,
    #[serde(default)]
    pub formats: Vec<YtDlpFormat>,
}

#[derive(Deserialize)]
pub struct YtDlpFormat {
    pub format_id: String,
    #[serde(default)]
    pub ext: Option<String>,
    #[serde(default)]
    pub height: Option<i64>,
    #[serde(default)]
    pub fps: Option<f64>,
    #[serde(default)]
    pub vcodec: Option<String>,
    #[serde(default)]
    pub acodec: Option<String>,
    #[serde(default)]
    pub filesize: Option<i64>,
    #[serde(default)]
    pub filesize_approx: Option<i64>,
    #[serde(default)]
    pub tbr: Option<f64>,
    #[serde(default)]
    pub format_note: Option<String>,
}

#[derive(Serialize)]
pub struct VideoInfo {
    pub id: String,
    pub title: String,
    pub thumbnail: Option<String>,
    pub duration: Option<f64>,
    pub formats: Vec<VideoFormat>,
}

#[derive(Serialize)]
pub struct VideoFormat {
    pub format_id: String,
    pub ext: String,
    pub height: Option<i64>,
    pub fps: Option<f64>,
    pub vcodec: String,
    pub acodec: String,
    pub has_video: bool,
    pub has_audio: bool,
    pub filesize: Option<i64>,
    pub tbr: Option<f64>,
    pub format_note: Option<String>,
}

impl From<YtDlpFormat> for VideoFormat {
    fn from(f: YtDlpFormat) -> Self {
        let vcodec = f.vcodec.unwrap_or_else(|| "none".to_string());
        let acodec = f.acodec.unwrap_or_else(|| "none".to_string());
        Self {
            format_id: f.format_id,
            ext: f.ext.unwrap_or_default(),
            height: f.height,
            fps: f.fps,
            has_video: vcodec != "none",
            has_audio: acodec != "none",
            vcodec,
            acodec,
            filesize: f.filesize.or(f.filesize_approx),
            tbr: f.tbr,
            format_note: f.format_note,
        }
    }
}

impl From<YtDlpInfo> for VideoInfo {
    fn from(info: YtDlpInfo) -> Self {
        Self {
            id: info.id,
            title: info.title,
            thumbnail: info.thumbnail,
            duration: info.duration,
            formats: info.formats.into_iter().map(VideoFormat::from).collect(),
        }
    }
}

#[derive(Clone, Serialize)]
pub struct DownloadProgress {
    pub download_id: i64,
    pub percent: String,
    pub speed: String,
    pub eta: String,
}

#[derive(Serialize)]
pub struct DownloadRecord {
    pub id: i64,
    pub url: String,
    pub title: String,
    pub format_selector: String,
    pub output_dir: String,
    pub output_path: Option<String>,
    pub status: String,
    pub error_message: Option<String>,
    pub created_at: String,
}
