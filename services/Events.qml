pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n

// Calendar events read from iCalendar files.
//
// Every *.ics file under $XDG_DATA_HOME/calendars (the vdir layout used by khal/vdirsyncer, and
// where apps such as LangSpot publish their calendars) is shown on the dashboard calendar.
// Read-only. Recurrence rules are not expanded: a recurring event shows its first occurrence.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_DATA_HOME") || `${Quickshell.env("HOME")}/.local/share`}/calendars`

    // Sorted by start: { uid, title, location, url, start: Date, end: Date, allDay: bool }
    property var events: []
    // "yyyy-MM-dd" -> number of events touching that day
    property var dayCounts: ({})
    readonly property bool available: events.length > 0

    function dayKey(date: date): string {
        return Qt.formatDate(date, "yyyy-MM-dd");
    }

    function count(date: date): int {
        return dayCounts[dayKey(date)] ?? 0;
    }

    function eventsOn(date: date): var {
        const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        const end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 1);
        return events.filter(e => e.start < end && (e.end > start || (+e.end === +e.start && e.start >= start)));
    }

    function nextAfter(date: date): var {
        const now = new Date();
        const from = date > now ? date : now;
        return events.find(e => e.start >= from) ?? null;
    }

    function reload(): void {
        readProc.running = true;
    }

    // ------------------------------------------------------------------ parsing
    function unescapeText(value: string): string {
        return value.replace(/\\([\\;,nN])/g, (_m, c) => (c === "n" || c === "N") ? "\n" : c);
    }

    function parseDate(value: string, params: string): var {
        const m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/.exec(value.trim());
        if (!m)
            return null;
        const [y, mo, d] = [+m[1], +m[2] - 1, +m[3]];
        if (!m[4] || /VALUE=DATE(?!-)/i.test(params))
            return {
                date: new Date(y, mo, d),
                allDay: true
            };
        // UTC when it ends in Z; floating or TZID times are taken as local time.
        const date = m[7] ? new Date(Date.UTC(y, mo, d, +m[4], +m[5], +m[6])) : new Date(y, mo, d, +m[4], +m[5], +m[6]);
        return {
            date,
            allDay: false
        };
    }

    function parseDuration(value: string): int {
        const m = /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(value.trim());
        if (!m)
            return 0;
        const ms = ((+(m[2] ?? 0) * 7 + +(m[3] ?? 0)) * 86400 + +(m[4] ?? 0) * 3600 + +(m[5] ?? 0) * 60 + +(m[6] ?? 0)) * 1000;
        return m[1] === "-" ? -ms : ms;
    }

    function parse(text: string): var {
        const lines = text.replace(/\r\n?/g, "\n").replace(/\n[ \t]/g, "").split("\n");
        const parsed = [];
        const seen = new Set();
        let current = null;
        for (const line of lines) {
            if (line === "BEGIN:VEVENT") {
                current = {};
                continue;
            }
            if (line === "END:VEVENT") {
                if (current?.start && current.status !== "CANCELLED") {
                    const key = `${current.uid ?? ""}|${+current.start.date}`;
                    if (!seen.has(key)) {
                        seen.add(key);
                        const start = current.start.date;
                        let end = current.end?.date ?? null;
                        if (!end && current.duration)
                            end = new Date(+start + current.duration);
                        if (!end)
                            end = current.start.allDay ? new Date(start.getFullYear(), start.getMonth(), start.getDate() + 1) : start;
                        parsed.push({
                            uid: current.uid ?? "",
                            title: current.summary || Tr.tr("(untitled)"),
                            location: current.location ?? "",
                            url: current.url ?? (/^https?:\/\//.test(current.location ?? "") ? current.location : ""),
                            start,
                            end: end < start ? start : end,
                            allDay: current.start.allDay
                        });
                    }
                }
                current = null;
                continue;
            }
            if (!current)
                continue;
            const colon = line.indexOf(":");
            if (colon < 0)
                continue;
            const head = line.slice(0, colon);
            const value = line.slice(colon + 1);
            const semi = head.indexOf(";");
            const name = (semi < 0 ? head : head.slice(0, semi)).toUpperCase();
            const params = semi < 0 ? "" : head.slice(semi + 1);
            switch (name) {
            case "UID":
                current.uid = value;
                break;
            case "SUMMARY":
                current.summary = unescapeText(value).trim();
                break;
            case "LOCATION":
                current.location = unescapeText(value).trim();
                break;
            case "URL":
                current.url = value.trim();
                break;
            case "STATUS":
                current.status = value.trim().toUpperCase();
                break;
            case "DTSTART":
                current.start = parseDate(value, params);
                break;
            case "DTEND":
                current.end = parseDate(value, params);
                break;
            case "DURATION":
                current.duration = parseDuration(value);
                break;
            }
        }
        return parsed.sort((a, b) => a.start - b.start || a.title.localeCompare(b.title));
    }

    function countDays(list: var): var {
        const counts = {};
        for (const e of list) {
            const day = new Date(e.start.getFullYear(), e.start.getMonth(), e.start.getDate());
            // An event ending exactly at midnight does not touch the next day.
            const last = new Date(+e.end - (+e.end > +e.start ? 1 : 0));
            for (let i = 0; i < 62 && day <= last; i++) {
                const key = dayKey(day);
                counts[key] = (counts[key] ?? 0) + 1;
                day.setDate(day.getDate() + 1);
            }
        }
        return counts;
    }

    function load(text: string): void {
        const list = parse(text);
        events = list;
        dayCounts = countDays(list);
    }

    Process {
        id: readProc

        // -L follows symlinked calendars; missing directory = no events.
        command: ["sh", "-c", "[ -d \"$1\" ] && find -L \"$1\" -type f -name '*.ics' -exec cat -- {} + 2>/dev/null; true", "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: root.load(text)
        }
    }

    Timer {
        // Calendar files are small; re-reading every 30 s also catches atomically replaced files.
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 30000
        onTriggered: root.reload()
    }

    IpcHandler {
        target: "events"

        function reload(): void {
            root.reload();
        }

        function list(): string {
            return root.events.map(e => `${e.start.toISOString()}\t${e.allDay ? "all-day" : e.end.toISOString()}\t${e.title}`).join("\n");
        }
    }
}
