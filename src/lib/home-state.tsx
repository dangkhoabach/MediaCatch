import { createContext, useContext, useState, type Dispatch, type ReactNode, type SetStateAction } from "react";
import type { VideoInfo } from "@/types/download";

export interface BatchItem {
  url: string;
  status: "pending" | "working" | "done" | "error";
  message?: string;
}

interface HomeStateValue {
  url: string;
  setUrl: Dispatch<SetStateAction<string>>;
  loading: boolean;
  setLoading: Dispatch<SetStateAction<boolean>>;
  info: VideoInfo | null;
  setInfo: Dispatch<SetStateAction<VideoInfo | null>>;
  platform: string | null;
  setPlatform: Dispatch<SetStateAction<string | null>>;
  selectedFormatId: string | null;
  setSelectedFormatId: Dispatch<SetStateAction<string | null>>;
  audioOnly: boolean;
  setAudioOnly: Dispatch<SetStateAction<boolean>>;
  starting: boolean;
  setStarting: Dispatch<SetStateAction<boolean>>;
  batchMode: boolean;
  setBatchMode: Dispatch<SetStateAction<boolean>>;
  batchText: string;
  setBatchText: Dispatch<SetStateAction<string>>;
  batchItems: BatchItem[];
  setBatchItems: Dispatch<SetStateAction<BatchItem[]>>;
  batchRunning: boolean;
  setBatchRunning: Dispatch<SetStateAction<boolean>>;
}

const HomeStateContext = createContext<HomeStateValue | null>(null);

/**
 * Home page state lives here, above the router, so it survives navigating
 * away to another tab and back — <HomePage> itself gets unmounted/remounted
 * by react-router on every route change, which used to wipe the fetched
 * video info and batch list.
 */
export function HomeStateProvider({ children }: { children: ReactNode }) {
  const [url, setUrl] = useState("");
  const [loading, setLoading] = useState(false);
  const [info, setInfo] = useState<VideoInfo | null>(null);
  const [platform, setPlatform] = useState<string | null>(null);
  const [selectedFormatId, setSelectedFormatId] = useState<string | null>(null);
  const [audioOnly, setAudioOnly] = useState(false);
  const [starting, setStarting] = useState(false);
  const [batchMode, setBatchMode] = useState(false);
  const [batchText, setBatchText] = useState("");
  const [batchItems, setBatchItems] = useState<BatchItem[]>([]);
  const [batchRunning, setBatchRunning] = useState(false);

  const value: HomeStateValue = {
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
  };

  return <HomeStateContext.Provider value={value}>{children}</HomeStateContext.Provider>;
}

export function useHomeState() {
  const ctx = useContext(HomeStateContext);
  if (!ctx) throw new Error("useHomeState must be used within HomeStateProvider");
  return ctx;
}
