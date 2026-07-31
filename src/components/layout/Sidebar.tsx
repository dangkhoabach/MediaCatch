import { Download, History, ListVideo, Settings } from "lucide-react";
import { NavLink } from "react-router";
import { cn } from "@/lib/utils";

const navItems = [
  { to: "/", label: "Tải mới", icon: Download, end: true },
  { to: "/queue", label: "Hàng đợi", icon: ListVideo, end: true },
  { to: "/library", label: "Lịch sử", icon: History, end: true },
  { to: "/settings", label: "Cài đặt", icon: Settings, end: true },
];

export function Sidebar() {
  return (
    <aside className="flex w-52 shrink-0 flex-col gap-1 border-r border-sidebar-border bg-sidebar pt-11 pb-4">
      <div className="mb-3 flex items-center gap-2 px-4">
        <span className="text-sm font-semibold tracking-tight">DKB Downloader</span>
      </div>

      <nav className="flex flex-1 flex-col gap-0.5 px-2">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            className={({ isActive }) =>
              cn(
                "flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm font-medium transition-colors",
                isActive
                  ? "bg-sidebar-accent text-sidebar-accent-foreground"
                  : "text-sidebar-foreground/70 hover:bg-sidebar-accent/60 hover:text-sidebar-foreground",
              )
            }
          >
            <item.icon className="size-4" />
            <span className="flex-1">{item.label}</span>
          </NavLink>
        ))}
      </nav>
    </aside>
  );
}
