import { HashRouter, Route, Routes } from "react-router";
import { Toaster } from "@/components/ui/sonner";
import { Sidebar } from "@/components/layout/Sidebar";
import { HomePage } from "@/pages/Home";
import { QueuePage } from "@/pages/Queue";
import { LibraryPage } from "@/pages/Library";
import { SettingsPage } from "@/pages/Settings";

function App() {
  return (
    <HashRouter>
      <div className="flex h-screen text-foreground">
        <div data-tauri-drag-region className="fixed inset-x-0 top-0 z-30 h-11" />
        <Sidebar />
        <main className="flex flex-1 flex-col overflow-hidden">
          <Routes>
            <Route path="/" element={<HomePage />} />
            <Route path="/queue" element={<QueuePage />} />
            <Route path="/library" element={<LibraryPage />} />
            <Route path="/settings" element={<SettingsPage />} />
          </Routes>
        </main>
        <Toaster />
      </div>
    </HashRouter>
  );
}

export default App;
