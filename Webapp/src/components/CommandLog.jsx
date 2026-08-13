// src/components/CommandLog.jsx
import { useState, useEffect } from "react";
import { ref, query, limitToLast, onValue } from "firebase/database";
import { db } from "../firebase";

function timeAgo(ts) {
  if (!ts) return "";
  const diff = Math.floor((Date.now() - ts) / 1000);
  if (diff < 60)   return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  return `${Math.floor(diff / 3600)}h ago`;
}

const sourceIcon = {
  telegram:       "✈️",
  telegram_voice: "🎙️",
  web_admin:      "🌐",
};

export default function CommandLog({ maxItems = 20 }) {
  const [logs, setLogs] = useState([]);

  useEffect(() => {
    const q = query(ref(db, "/meka/command_log"), limitToLast(maxItems));
    const unsub = onValue(q, snap => {
      const data = snap.val();
      if (!data) { setLogs([]); return; }
      const arr = Object.entries(data)
        .map(([k, v]) => ({ id: k, ...v }))
        .sort((a, b) => (b.ts || 0) - (a.ts || 0));
      setLogs(arr);
    });
    return () => unsub();
  }, [maxItems]);

  if (logs.length === 0) {
    return (
      <div style={{ textAlign: "center", padding: "2rem", color: "var(--text-dim)", fontSize: "0.88rem" }}>
        No commands yet. Send a message to MEKA on Telegram!
      </div>
    );
  }

  return (
    <div>
      {logs.map(log => (
        <div key={log.id} className="log-entry">
          <span style={{ fontSize: "1.1rem", flexShrink: 0 }}>
            {sourceIcon[log.source] || "🤖"}
          </span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
              <span className="log-command" style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {log.command}
              </span>
              {log.user_email && (
                <span style={{ fontSize: "0.65rem", padding: "1px 5px", borderRadius: 4, background: "rgba(255,255,255,0.06)", color: "var(--text-dim)", fontFamily: "monospace" }}>
                  {log.user_email}
                </span>
              )}
            </div>
            <div className="log-response" style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
              {log.response}
            </div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 4, flexShrink: 0 }}>
            <span className={`tag ${log.status === "success" ? "tag-green" : "tag-red"}`} style={{ fontSize: "0.65rem" }}>
              {log.status}
            </span>
            <span className="log-time">{timeAgo(log.ts)}</span>
          </div>
        </div>
      ))}
    </div>
  );
}
