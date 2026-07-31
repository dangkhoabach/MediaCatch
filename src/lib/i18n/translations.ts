export const translations = {
  en: {
    "app.name": "DKB Downloader",

    "nav.home": "New Download",
    "nav.queue": "Queue",
    "nav.library": "Library",
    "nav.settings": "Settings",

    "home.urlPlaceholder": "Paste a YouTube link...",
    "home.fetchInfo": "Fetch Info",
    "home.fetchError": "Couldn't fetch video info",
    "home.audioOnly": "Audio only",
    "home.hasAudio": "with audio",
    "home.noAudio": "no audio",
    "home.noFormatSelected": "No quality selected",
    "home.downloadStarted": "Download started",
    "home.downloadStartError": "Couldn't start download",
    "home.download": "Download",

    "queue.empty": "No downloads in progress",
    "queue.eta": "ETA {eta}",

    "library.empty": "No videos in your library yet",
    "library.deleteError": "Couldn't delete",
    "library.status.downloading": "Downloading",
    "library.status.completed": "Completed",
    "library.status.error": "Error",
    "library.status.canceled": "Canceled",

    "settings.outputDir": "Default download folder",
    "settings.outputFormat": "Default output format",
    "settings.theme": "Theme",
    "settings.theme.light": "Light",
    "settings.theme.dark": "Dark",
    "settings.theme.system": "System",
    "settings.language": "Language",
    "settings.notifications": "Notifications",
    "settings.notificationsHint": "Notify me when a download finishes or fails",
    "settings.notificationsPermissionHint": "If you don't see a notification, macOS may be blocking it",
    "settings.openSettings": "Open Settings",

    "notification.downloadComplete.title": "Download complete",
    "notification.downloadError.title": "Download failed",
    "notification.ytdlpUpdated.title": "yt-dlp updated",
    "notification.ytdlpUpdated.body": "Updated to version {version}",
  },
  vi: {
    "app.name": "DKB Downloader",

    "nav.home": "Tải mới",
    "nav.queue": "Hàng đợi",
    "nav.library": "Lịch sử",
    "nav.settings": "Cài đặt",

    "home.urlPlaceholder": "Dán link YouTube...",
    "home.fetchInfo": "Lấy thông tin",
    "home.fetchError": "Không lấy được thông tin video",
    "home.audioOnly": "Chỉ tải âm thanh",
    "home.hasAudio": "có tiếng",
    "home.noAudio": "không tiếng",
    "home.noFormatSelected": "Chưa chọn chất lượng",
    "home.downloadStarted": "Đã bắt đầu tải",
    "home.downloadStartError": "Không thể bắt đầu tải",
    "home.download": "Tải xuống",

    "queue.empty": "Không có tải nào đang chạy",
    "queue.eta": "Còn lại {eta}",

    "library.empty": "Chưa có video nào trong lịch sử",
    "library.deleteError": "Không xoá được",
    "library.status.downloading": "Đang tải",
    "library.status.completed": "Hoàn tất",
    "library.status.error": "Lỗi",
    "library.status.canceled": "Đã huỷ",

    "settings.outputDir": "Thư mục lưu mặc định",
    "settings.outputFormat": "Định dạng output mặc định",
    "settings.theme": "Giao diện",
    "settings.theme.light": "Sáng",
    "settings.theme.dark": "Tối",
    "settings.theme.system": "Theo hệ thống",
    "settings.language": "Ngôn ngữ",
    "settings.notifications": "Thông báo",
    "settings.notificationsHint": "Báo khi tải xong hoặc tải lỗi",
    "settings.notificationsPermissionHint": "Nếu không thấy thông báo, macOS có thể đang chặn",
    "settings.openSettings": "Mở Cài đặt",

    "notification.downloadComplete.title": "Đã tải xong",
    "notification.downloadError.title": "Tải thất bại",
    "notification.ytdlpUpdated.title": "Đã cập nhật yt-dlp",
    "notification.ytdlpUpdated.body": "Đã cập nhật lên phiên bản {version}",
  },
} as const;

export type Locale = keyof typeof translations;
export type TranslationKey = keyof (typeof translations)["en"];
