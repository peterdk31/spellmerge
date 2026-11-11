// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// What Cloudflare's TURN service answers, read (server/signal/README.md, "The relay"): the one
// file that knows its layout. worker.js makes the call; rooms.js is handed the plain relay this
// gives and knows nothing of where it came from. Another relay service is another file like this.

/**
 * The relay in the answer of Cloudflare's `generate-ice-servers`
 * (`{ iceServers: [{ urls }, { urls, username, credential }] }`): the first server with a user
 * name and a password, as `{ urls: [...], username, credential }`. null when there is none.
 * Nothing is checked here beyond that: rooms.js checks every address and word before it is sent.
 */
export function relayOfCloudflare(answer) {
  const servers = answer !== null && typeof answer === "object" ? answer.iceServers : undefined;
  if (!Array.isArray(servers)) return null;
  for (const server of servers) {
    if (server === null || typeof server !== "object") continue;
    const { urls, username, credential } = server;
    if (typeof username !== "string" || typeof credential !== "string") continue;
    return { urls: Array.isArray(urls) ? urls : [urls], username, credential };
  }
  return null;
}
